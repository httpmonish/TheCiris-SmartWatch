"""
==============================================================================
CIRIS WEARABLE PRODUCTION ML & DATA ENGINEERING PIPELINE ENGINE
==============================================================================
Comprehensive End-to-End Engine:
  - Ingestion (CSV / JSON / Parquet) with schema & type inference
  - Validation (Range checks, constraints, quality audit, error ledger)
  - Data Cleaning & Deterministic Preprocessing
  - Exploratory Data Analysis (EDA, distributions, correlation matrix)
  - Feature Engineering (Domain physiological/environmental composites)
  - Multi-Model Training & Evaluation (Logistic, Random Forest, MLP)
  - Model Registry & Artifact Management
  - Local & Global Explainability Engine (Feature Contributions)
  - Real-time Calibrated Prediction Service
==============================================================================
"""

import sys
import os
import json
import math
import hashlib
import time
import random
import sqlite3
import argparse
from typing import Dict, List, Any, Tuple, Optional

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, confusion_matrix, roc_auc_score
from sklearn.preprocessing import StandardScaler
import joblib

# Database path resolution
DEFAULT_DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "database", "ciris_platform.db"))
MODELS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "models"))

# Physical domain constraints for validation
DOMAIN_CONSTRAINTS = {
    "heart_rate_bpm": {"min": 20.0, "max": 250.0, "warn_min": 40.0, "warn_max": 200.0, "type": "float"},
    "rmssd_ms": {"min": 0.0, "max": 300.0, "warn_min": 2.0, "warn_max": 200.0, "type": "float"},
    "spo2_pct": {"min": 50.0, "max": 100.0, "warn_min": 70.0, "warn_max": 100.0, "type": "float"},
    "skin_temp_c": {"min": 20.0, "max": 50.0, "warn_min": 28.0, "warn_max": 43.0, "type": "float"},
    "ambient_temp_c": {"min": -40.0, "max": 70.0, "warn_min": -15.0, "warn_max": 55.0, "type": "float"},
    "ambient_humidity_pct": {"min": 0.0, "max": 100.0, "warn_min": 5.0, "warn_max": 100.0, "type": "float"},
    "imu_jerk_ms3": {"min": 0.0, "max": 200.0, "warn_min": 0.0, "warn_max": 70.0, "type": "float"},
    "aqi_ppm": {"min": 0.0, "max": 1000.0, "warn_min": 0.0, "warn_max": 500.0, "type": "float"},
    "barometric_pressure_hpa": {"min": 500.0, "max": 1200.0, "warn_min": 650.0, "warn_max": 1050.0, "type": "float"},
    "flood_threat_index": {"min": 0.0, "max": 1.0, "warn_min": 0.0, "warn_max": 1.0, "type": "float"},
}

RAW_FEATURE_COLUMNS = [
    "heart_rate_bpm", "rmssd_ms", "spo2_pct", "skin_temp_c",
    "ambient_temp_c", "ambient_humidity_pct", "imu_jerk_ms3",
    "aqi_ppm", "barometric_pressure_hpa", "flood_threat_index"
]

ENGINEERED_FEATURE_COLUMNS = [
    "cardiac_strain_index",
    "thermal_heat_stress",
    "hypoxia_depth",
    "shock_motion_index",
    "barometric_anomaly"
]

ALL_FEATURE_COLUMNS = RAW_FEATURE_COLUMNS + ENGINEERED_FEATURE_COLUMNS

RISK_CLASS_MAP = {
    0: {"name": "Normal / Routine", "tier": "NOMINAL_GREEN", "code": 0},
    1: {"name": "Environmental & Heat Strain", "tier": "WARNING_ORANGE", "code": 1},
    2: {"name": "Life Emergency & Disaster Threat", "tier": "CRITICAL_RED", "code": 2}
}


def get_db_connection(db_path: str = DEFAULT_DB_PATH) -> sqlite3.Connection:
    """Connect to SQLite database with timeout."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


# =============================================================================
# 1. INGESTION & SCHEMA INFERENCE
# =============================================================================

def compute_file_hash(file_path: str) -> str:
    """Compute SHA-256 hash of a file for versioning and provenance."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def ingest_dataset_file(file_path: str, dataset_name: Optional[str] = None, db_path: str = DEFAULT_DB_PATH) -> Dict[str, Any]:
    """
    Ingest a raw dataset (CSV or JSON), infer schema, generate metadata,
    and persist into database.
    """
    start_time = time.time()
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Dataset file not found: {file_path}")

    ext = os.path.splitext(file_path)[1].lower()
    file_size = os.path.getsize(file_path)
    file_hash = compute_file_hash(file_path)
    ds_name = dataset_name or os.path.basename(file_path)
    dataset_id = f"ds_{hashlib.md5(f'{ds_name}_{file_hash}'.encode()).hexdigest()[:12]}"

    if ext == ".csv":
        df = pd.read_csv(file_path)
        file_format = "csv"
    elif ext == ".json":
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and "features" in data:
            df = pd.DataFrame(data["features"], columns=RAW_FEATURE_COLUMNS)
            if "labels" in data:
                df["risk_class"] = data["labels"]
            if "scenarios" in data:
                df["scenario_tag"] = data["scenarios"]
        else:
            df = pd.DataFrame(data)
        file_format = "json"
    else:
        raise ValueError(f"Unsupported file format: {ext}")

    row_count, col_count = df.shape
    columns_detected = list(df.columns)
    dtypes_detected = {col: str(dtype) for col, dtype in df.dtypes.items()}

    # Connect to DB and register dataset
    conn = get_db_connection(db_path)
    try:
        with conn:
            # Check if dataset already registered
            existing = conn.execute("SELECT version FROM datasets WHERE dataset_id = ?", (dataset_id,)).fetchone()
            version = 1 if not existing else existing["version"] + 1

            meta = {
                "columns_detected": columns_detected,
                "dtypes_detected": dtypes_detected,
                "original_filename": os.path.basename(file_path),
                "ingestion_duration_ms": round((time.time() - start_time) * 1000, 2)
            }

            conn.execute("""
                INSERT OR REPLACE INTO datasets (
                    dataset_id, name, version, file_format, file_size_bytes,
                    checksum_sha256, row_count, column_count, status, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'UPLOADED', ?)
            """, (
                dataset_id, ds_name, version, file_format, file_size,
                file_hash, row_count, col_count, json.dumps(meta)
            ))
    finally:
        conn.close()

    duration_ms = round((time.time() - start_time) * 1000, 2)
    return {
        "dataset_id": dataset_id,
        "name": ds_name,
        "version": version,
        "file_format": file_format,
        "file_size_bytes": file_size,
        "checksum_sha256": file_hash,
        "row_count": row_count,
        "column_count": col_count,
        "columns_detected": columns_detected,
        "dtypes_detected": dtypes_detected,
        "duration_ms": duration_ms
    }


# =============================================================================
# 2. DATA VALIDATION & QUALITY AUDIT
# =============================================================================

def validate_and_load_dataset(dataset_id: str, file_path: str, db_path: str = DEFAULT_DB_PATH) -> Dict[str, Any]:
    """
    Run multi-level data validation against physical sensor constraints,
    record validation errors, compute quality score, and insert cleaned records into DB.
    """
    start_time = time.time()
    conn = get_db_connection(db_path)

    try:
        conn.execute("UPDATE datasets SET status = 'VALIDATING' WHERE dataset_id = ?", (dataset_id,))
        conn.commit()

        # Load dataframe
        if file_path.endswith(".csv"):
            df = pd.read_csv(file_path)
        else:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and "features" in data:
                df = pd.DataFrame(data["features"], columns=RAW_FEATURE_COLUMNS)
                if "labels" in data:
                    df["risk_class"] = data["labels"]
                if "scenarios" in data:
                    df["scenario_tag"] = data["scenarios"]
            else:
                df = pd.DataFrame(data)

        total_rows = len(df)
        validation_errors = []
        missing_values_count = int(df.isnull().sum().sum())
        duplicate_rows = int(df.duplicated(subset=[c for c in RAW_FEATURE_COLUMNS if c in df.columns]).sum())

        # Check required columns
        missing_required = [c for c in RAW_FEATURE_COLUMNS if c not in df.columns]
        if missing_required:
            validation_errors.append({
                "row_index": -1,
                "field_name": "SCHEMA",
                "error_type": "MISSING_COLUMNS",
                "error_message": f"Missing mandatory sensor features: {missing_required}",
                "raw_value": None
            })

        # Validate sensor bounds
        invalid_rows_set = set()
        for field, rules in DOMAIN_CONSTRAINTS.items():
            if field in df.columns:
                out_of_bounds = df[(df[field] < rules["min"]) | (df[field] > rules["max"])]
                for idx, row in out_of_bounds.iterrows():
                    invalid_rows_set.add(idx)
                    if len(validation_errors) < 500:  # Cap logged errors
                        validation_errors.append({
                            "row_index": int(idx),
                            "field_name": field,
                            "error_type": "PHYSICAL_RANGE_VIOLATION",
                            "error_message": f"Value {row[field]} outside physiological bounds [{rules['min']}, {rules['max']}]",
                            "raw_value": str(row[field])
                        })

        invalid_rows = len(invalid_rows_set)
        valid_rows = total_rows - invalid_rows

        # Calculate composite Quality Score (0 to 100)
        quality_score = max(0.0, min(100.0, 100.0 - (invalid_rows / max(1, total_rows) * 50.0) - (missing_values_count / max(1, total_rows * len(df.columns)) * 30.0) - (duplicate_rows / max(1, total_rows) * 20.0)))
        quality_score = round(quality_score, 2)

        status = "PASS" if quality_score >= 90.0 and not missing_required else ("WARNING" if quality_score >= 70.0 else "FAIL")

        # Save validation errors to DB
        with conn:
            conn.execute("DELETE FROM validation_errors WHERE dataset_id = ?", (dataset_id,))
            for err in validation_errors[:200]:
                conn.execute("""
                    INSERT INTO validation_errors (dataset_id, row_index, field_name, error_type, error_message, raw_value)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (dataset_id, err["row_index"], err["field_name"], err["error_type"], err["error_message"], err["raw_value"]))

            report_payload = {
                "dataset_id": dataset_id,
                "status": status,
                "quality_score": quality_score,
                "total_rows": total_rows,
                "valid_rows": valid_rows,
                "invalid_rows": invalid_rows,
                "duplicate_rows": duplicate_rows,
                "missing_values_count": missing_values_count,
                "error_count": len(validation_errors),
                "missing_required_columns": missing_required
            }

            conn.execute("""
                INSERT OR REPLACE INTO validation_reports (
                    dataset_id, status, total_rows, valid_rows, invalid_rows,
                    duplicate_rows, missing_values_count, quality_score,
                    validation_duration_ms, report_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                dataset_id, status, total_rows, valid_rows, invalid_rows,
                duplicate_rows, missing_values_count, quality_score,
                int((time.time() - start_time) * 1000), json.dumps(report_payload)
            ))

            conn.execute("UPDATE datasets SET status = 'VALIDATED' WHERE dataset_id = ?", (dataset_id,))

        # Ingest cleaned records into dataset_records table
        # We clean and stream valid records
        df_cleaned = df.drop(index=list(invalid_rows_set)) if invalid_rows_set else df.copy()

        # Fill missing values deterministically if any
        for col in RAW_FEATURE_COLUMNS:
            if col in df_cleaned.columns and df_cleaned[col].isnull().any():
                df_cleaned[col] = df_cleaned[col].fillna(df_cleaned[col].median())

        # Ensure target and tag columns exist
        if "sample_id" not in df_cleaned.columns:
            df_cleaned["sample_id"] = range(1, len(df_cleaned) + 1)
        if "scenario_tag" not in df_cleaned.columns:
            df_cleaned["scenario_tag"] = "Auto-Ingested Stream"
        if "risk_class" not in df_cleaned.columns:
            df_cleaned["risk_class"] = 0
        if "risk_tier" not in df_cleaned.columns:
            df_cleaned["risk_tier"] = df_cleaned["risk_class"].map({0: "NOMINAL_GREEN", 1: "WARNING_ORANGE", 2: "CRITICAL_RED"}).fillna("NOMINAL_GREEN")

        # Insert records into database (up to 50,000 for fast DB responsiveness)
        insert_rows = []
        limit_db_rows = min(50000, len(df_cleaned))
        for _, r in df_cleaned.head(limit_db_rows).iterrows():
            insert_rows.append((
                dataset_id, int(r["sample_id"]), str(r["scenario_tag"]),
                float(r["heart_rate_bpm"]), float(r["rmssd_ms"]), float(r["spo2_pct"]),
                float(r["skin_temp_c"]), float(r["ambient_temp_c"]), float(r["ambient_humidity_pct"]),
                float(r["imu_jerk_ms3"]), float(r["aqi_ppm"]), float(r["barometric_pressure_hpa"]),
                float(r["flood_threat_index"]), int(r["risk_class"]), str(r["risk_tier"])
            ))

        with conn:
            conn.execute("DELETE FROM dataset_records WHERE dataset_id = ?", (dataset_id,))
            conn.executemany("""
                INSERT INTO dataset_records (
                    dataset_id, sample_id, scenario_tag, heart_rate_bpm, rmssd_ms,
                    spo2_pct, skin_temp_c, ambient_temp_c, ambient_humidity_pct,
                    imu_jerk_ms3, aqi_ppm, barometric_pressure_hpa, flood_threat_index,
                    risk_class, risk_tier
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, insert_rows)

            conn.execute("UPDATE datasets SET status = 'PROCESSED' WHERE dataset_id = ?", (dataset_id,))

        duration_ms = int((time.time() - start_time) * 1000)
        return {
            "dataset_id": dataset_id,
            "status": status,
            "quality_score": quality_score,
            "total_rows": total_rows,
            "valid_rows": valid_rows,
            "invalid_rows": invalid_rows,
            "duplicate_rows": duplicate_rows,
            "missing_values": missing_values_count,
            "duration_ms": duration_ms
        }

    finally:
        conn.close()


# =============================================================================
# 3. STATISTICAL EDA & ANALYTICS ENGINE
# =============================================================================

def compute_and_cache_eda(dataset_id: str, file_path: Optional[str] = None, db_path: str = DEFAULT_DB_PATH) -> Dict[str, Any]:
    """
    Compute comprehensive summary statistics, percentiles, histograms,
    correlation matrix, and class distributions.
    """
    conn = get_db_connection(db_path)
    try:
        if file_path and os.path.exists(file_path):
            if file_path.endswith(".csv"):
                df = pd.read_csv(file_path)
            else:
                with open(file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                df = pd.DataFrame(data["features"], columns=RAW_FEATURE_COLUMNS)
                if "labels" in data:
                    df["risk_class"] = data["labels"]
                if "scenarios" in data:
                    df["scenario_tag"] = data["scenarios"]
        else:
            # Load from DB
            records = conn.execute("SELECT * FROM dataset_records WHERE dataset_id = ?", (dataset_id,)).fetchall()
            if not records:
                raise ValueError(f"No records found for dataset {dataset_id}")
            df = pd.DataFrame([dict(r) for r in records])

        # 1. Summary Statistics per feature
        summary_stats = {}
        for col in RAW_FEATURE_COLUMNS:
            if col in df.columns:
                series = df[col].dropna()
                summary_stats[col] = {
                    "count": int(len(series)),
                    "mean": round(float(series.mean()), 3),
                    "std": round(float(series.std()), 3),
                    "min": round(float(series.min()), 3),
                    "q25": round(float(series.quantile(0.25)), 3),
                    "median": round(float(series.median()), 3),
                    "q75": round(float(series.quantile(0.75)), 3),
                    "max": round(float(series.max()), 3),
                    "skew": round(float(series.skew()), 3)
                }

        # 2. Correlation Matrix
        num_cols = [c for c in RAW_FEATURE_COLUMNS if c in df.columns]
        if "risk_class" in df.columns:
            num_cols.append("risk_class")
        corr_matrix = df[num_cols].corr().round(3).to_dict()

        # 3. Distribution Histograms (10 bins per feature for fast rendering)
        distributions = {}
        for col in RAW_FEATURE_COLUMNS:
            if col in df.columns:
                series = df[col].dropna()
                hist, bin_edges = np.histogram(series, bins=10)
                distributions[col] = {
                    "counts": hist.tolist(),
                    "bin_edges": [round(float(b), 2) for b in bin_edges]
                }

        # 4. Class & Scenario Distributions
        class_dist = df["risk_class"].value_counts(normalize=True).round(4).to_dict() if "risk_class" in df.columns else {}
        scenario_dist = df["scenario_tag"].value_counts().head(16).to_dict() if "scenario_tag" in df.columns else {}

        # Save to DB
        with conn:
            conn.execute("""
                INSERT OR REPLACE INTO eda_analytics (
                    dataset_id, summary_stats_json, correlations_json,
                    distributions_json, class_distribution_json, scenario_distribution_json
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (
                dataset_id, json.dumps(summary_stats), json.dumps(corr_matrix),
                json.dumps(distributions), json.dumps(class_dist), json.dumps(scenario_dist)
            ))
            conn.execute("UPDATE datasets SET status = 'ANALYZED' WHERE dataset_id = ?", (dataset_id,))

        return {
            "dataset_id": dataset_id,
            "summary_stats": summary_stats,
            "correlations": corr_matrix,
            "distributions": distributions,
            "class_distribution": class_dist,
            "scenario_distribution": scenario_dist
        }

    finally:
        conn.close()


# =============================================================================
# 4. FEATURE ENGINEERING PIPELINE
# =============================================================================

def apply_feature_engineering(df: pd.DataFrame) -> pd.DataFrame:
    """
    Generate domain-specific physiological and environmental composite features
    without data leakage.
    """
    df_out = df.copy()

    # Feature 1: Cardiac Strain Index = HR / (RMSSD + 1.0)
    # Higher values indicate sympathetic overdrive + low vagal tone
    df_out["cardiac_strain_index"] = (df_out["heart_rate_bpm"] / (df_out["rmssd_ms"] + 1.0)).round(3)

    # Feature 2: Thermal Heat Stress = Ambient Temp + 0.05 * Humidity
    df_out["thermal_heat_stress"] = (df_out["ambient_temp_c"] + 0.05 * df_out["ambient_humidity_pct"]).round(2)

    # Feature 3: Hypoxia Depth = max(0, 95.0 - SpO2)
    df_out["hypoxia_depth"] = (np.maximum(0.0, 95.0 - df_out["spo2_pct"])).round(2)

    # Feature 4: Shock Motion Index = Jerk * (HR / 70.0)
    # Highlights high-impact falls during panic/tachycardia
    df_out["shock_motion_index"] = (df_out["imu_jerk_ms3"] * (df_out["heart_rate_bpm"] / 70.0)).round(2)

    # Feature 5: Barometric Anomaly = |Pressure - 1013.25|
    df_out["barometric_anomaly"] = (np.abs(df_out["barometric_pressure_hpa"] - 1013.25)).round(2)

    return df_out


# =============================================================================
# 5. MODEL TRAINING, EVALUATION & REGISTRY
# =============================================================================

def train_and_register_model(
    dataset_id: str,
    file_path: str,
    algorithm: str = "random_forest",
    hyperparameters: Optional[Dict[str, Any]] = None,
    db_path: str = DEFAULT_DB_PATH
) -> Dict[str, Any]:
    """
    Train a production classifier with strict train/val/test splits (70/15/15),
    evaluate with multiple metrics, serialize weights & scaler, and register in model registry.
    """
    start_time = time.time()
    os.makedirs(MODELS_DIR, exist_ok=True)

    # Load dataset
    if file_path.endswith(".csv"):
        df = pd.read_csv(file_path)
    else:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        df = pd.DataFrame(data["features"], columns=RAW_FEATURE_COLUMNS)
        df["risk_class"] = data["labels"]

    # Apply Feature Engineering
    df_feat = apply_feature_engineering(df)
    X = df_feat[ALL_FEATURE_COLUMNS]
    y = df_feat["risk_class"].astype(int)

    # Train (70%), Val (15%), Test (15%) splits
    X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.30, random_state=42, stratify=y)
    X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.50, random_state=42, stratify=y_temp)

    # Fit scaler strictly on training split
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_val_scaled = scaler.transform(X_val)
    X_test_scaled = scaler.transform(X_test)

    # Instantiate model
    hp = hyperparameters or {}
    if algorithm == "random_forest":
        n_estimators = hp.get("n_estimators", 100)
        max_depth = hp.get("max_depth", 12)
        model = RandomForestClassifier(n_estimators=n_estimators, max_depth=max_depth, random_state=42, n_jobs=-1)
    elif algorithm == "logistic_regression":
        C = hp.get("C", 1.0)
        model = LogisticRegression(C=C, max_iter=500, random_state=42)
    elif algorithm == "mlp":
        hidden_layer_sizes = hp.get("hidden_layer_sizes", (64, 32))
        model = MLPClassifier(hidden_layer_sizes=hidden_layer_sizes, max_iter=200, random_state=42)
    else:
        raise ValueError(f"Unknown algorithm: {algorithm}")

    # Train model
    model.fit(X_train_scaled, y_train)

    # Predict on held-out test split
    y_pred = model.predict(X_test_scaled)
    y_proba = model.predict_proba(X_test_scaled)

    # Calculate metrics
    acc = float(accuracy_score(y_test, y_pred))
    prec, rec, f1, support = precision_recall_fscore_support(y_test, y_pred, average="weighted")
    cm = confusion_matrix(y_test, y_pred).tolist()

    # Per-class metrics
    prec_per, rec_per, f1_per, sup_per = precision_recall_fscore_support(y_test, y_pred, average=None)
    per_class_metrics = [
        {
            "class_id": i,
            "class_name": RISK_CLASS_MAP[i]["name"],
            "tier": RISK_CLASS_MAP[i]["tier"],
            "precision": round(float(prec_per[i]), 4),
            "recall": round(float(rec_per[i]), 4),
            "f1": round(float(f1_per[i]), 4),
            "support": int(sup_per[i])
        } for i in range(len(prec_per))
    ]

    # Global feature importances
    if hasattr(model, "feature_importances_"):
        raw_importances = model.feature_importances_
    elif hasattr(model, "coef_"):
        raw_importances = np.mean(np.abs(model.coef_), axis=0)
    else:
        raw_importances = np.ones(len(ALL_FEATURE_COLUMNS)) / len(ALL_FEATURE_COLUMNS)

    feature_importances = {
        feat: round(float(imp), 4)
        for feat, imp in sorted(zip(ALL_FEATURE_COLUMNS, raw_importances), key=lambda x: x[1], reverse=True)
    }

    # Model metadata and persistence
    model_version = f"v{int(time.time())}"
    model_id = f"model_{algorithm}_{model_version}"
    artifact_filename = f"{model_id}.joblib"
    artifact_path = os.path.join(MODELS_DIR, artifact_filename)

    joblib.dump({
        "model": model,
        "scaler": scaler,
        "feature_columns": ALL_FEATURE_COLUMNS,
        "raw_columns": RAW_FEATURE_COLUMNS,
        "engineered_columns": ENGINEERED_FEATURE_COLUMNS,
        "feature_importances": feature_importances,
        "algorithm": algorithm,
        "hyperparameters": hp,
        "metrics": {
            "accuracy": round(acc, 4),
            "precision": round(float(prec), 4),
            "recall": round(float(rec), 4),
            "f1": round(float(f1), 4)
        }
    }, artifact_path)

    metrics_payload = {
        "accuracy": round(acc, 4),
        "precision": round(float(prec), 4),
        "recall": round(float(rec), 4),
        "f1": round(float(f1), 4),
        "per_class": per_class_metrics,
        "feature_importances": feature_importances,
        "train_samples": len(X_train),
        "val_samples": len(X_val),
        "test_samples": len(X_test),
        "training_duration_ms": int((time.time() - start_time) * 1000)
    }

    # Register in SQLite database
    conn = get_db_connection(db_path)
    try:
        with conn:
            # Deactivate older models of same algorithm if production
            conn.execute("""
                INSERT INTO models (
                    model_id, model_name, version, algorithm, training_dataset_id,
                    feature_names_json, feature_preprocessing_json, hyperparameters_json,
                    metrics_json, confusion_matrix_json, artifact_path, status, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'production', 1)
            """, (
                model_id, f"CIRIS {algorithm.replace('_', ' ').title()} Classifier",
                model_version, algorithm, dataset_id,
                json.dumps(ALL_FEATURE_COLUMNS),
                json.dumps({"scaler": "StandardScaler", "means": scaler.mean_.tolist(), "stds": scaler.scale_.tolist()}),
                json.dumps(hp),
                json.dumps(metrics_payload),
                json.dumps(cm),
                artifact_path
            ))
            # Set other models as staging
            conn.execute("UPDATE models SET is_active = 0 WHERE model_id != ?", (model_id,))
    finally:
        conn.close()

    return {
        "model_id": model_id,
        "version": model_version,
        "algorithm": algorithm,
        "accuracy": round(acc, 4),
        "f1": round(float(f1), 4),
        "confusion_matrix": cm,
        "feature_importances": feature_importances,
        "artifact_path": artifact_path
    }


# =============================================================================
# 6. EXPLAINABILITY & PREDICTION SERVICE
# =============================================================================

_LOADED_MODEL_CACHE = {}

def get_active_model(model_id: Optional[str] = None, db_path: str = DEFAULT_DB_PATH):
    """Retrieve and cache active production model bundle."""
    global _LOADED_MODEL_CACHE

    conn = get_db_connection(db_path)
    try:
        if model_id:
            row = conn.execute("SELECT * FROM models WHERE model_id = ?", (model_id,)).fetchone()
        else:
            row = conn.execute("SELECT * FROM models WHERE is_active = 1 ORDER BY trained_at DESC LIMIT 1").fetchone()
            if not row:
                row = conn.execute("SELECT * FROM models ORDER BY trained_at DESC LIMIT 1").fetchone()

        if not row:
            return None

        m_id = row["model_id"]
        if m_id in _LOADED_MODEL_CACHE:
            return _LOADED_MODEL_CACHE[m_id]

        artifact_path = row["artifact_path"]
        if not os.path.exists(artifact_path):
            raise FileNotFoundError(f"Model artifact not found at: {artifact_path}")

        bundle = joblib.load(artifact_path)
        bundle["model_id"] = m_id
        bundle["version"] = row["version"]
        bundle["algorithm"] = row["algorithm"]
        _LOADED_MODEL_CACHE[m_id] = bundle
        return bundle
    finally:
        conn.close()


def predict_single_sample(
    input_data: Dict[str, float],
    model_id: Optional[str] = None,
    source: str = "API_REQUEST",
    db_path: str = DEFAULT_DB_PATH
) -> Dict[str, Any]:
    """
    Perform high-precision prediction with feature engineering,
    calibrated probabilities, and local explainability (feature attribution).
    """
    start_time = time.time()
    bundle = get_active_model(model_id, db_path)

    if not bundle:
        raise RuntimeError("No active ML model found in registry. Train a model first.")

    model = bundle["model"]
    scaler = bundle["scaler"]
    feature_cols = bundle["feature_columns"]

    # Check model domain type
    is_ciris_biosensor = ("heart_rate_bpm" in feature_cols or "cardiac_strain_index" in feature_cols)
    is_wisdm = "activity_map" in bundle or "accel_x_mean" in feature_cols
    is_kaggle = "action_classes" in bundle or "r_mean" in feature_cols

    validation_warnings = []
    sanitized_input = {}

    if is_ciris_biosensor:
        for f in RAW_FEATURE_COLUMNS:
            val = float(input_data.get(f, 0.0))
            rules = DOMAIN_CONSTRAINTS.get(f, {})
            if "min" in rules and "max" in rules:
                if val < rules["min"] or val > rules["max"]:
                    validation_warnings.append(f"{f}={val} outside physical bounds [{rules['min']}, {rules['max']}]")
                val = max(rules["min"], min(rules["max"], val))
            sanitized_input[f] = val

        df_raw = pd.DataFrame([sanitized_input])
        df_feat = apply_feature_engineering(df_raw)
        X = df_feat[feature_cols]
    else:
        # Generic / WISDM / Kaggle model
        for f in feature_cols:
            val = float(input_data.get(f, 0.0))
            sanitized_input[f] = val
        X = pd.DataFrame([sanitized_input])[feature_cols]

    # Scale features
    X_scaled = scaler.transform(X)

    # Inference
    probabilities = model.predict_proba(X_scaled)[0]
    pred_class = int(np.argmax(probabilities))
    confidence = float(probabilities[pred_class])

    if is_ciris_biosensor:
        class_meta = RISK_CLASS_MAP[pred_class]
        pred_label = class_meta["name"]
        pred_tier = class_meta["tier"]
        probs_dict = {
            "class_0_normal": round(float(probabilities[0]), 4),
            "class_1_strain": round(float(probabilities[1]), 4),
            "class_2_emergency": round(float(probabilities[2]), 4)
        }
    elif is_wisdm:
        id_to_name = bundle.get("id_to_name", {})
        id_to_cat = bundle.get("id_to_category", {})
        pred_label = id_to_name.get(pred_class, f"Activity_{pred_class}")
        pred_tier = id_to_cat.get(pred_class, "ACTIVITY")
        probs_dict = {id_to_name.get(i, f"act_{i}"): round(float(p), 4) for i, p in enumerate(probabilities)}
    elif is_kaggle:
        action_classes = bundle.get("action_classes", [])
        pred_label = action_classes[pred_class] if pred_class < len(action_classes) else f"Action_{pred_class}"
        pred_tier = "ACTION_RECOGNITION"
        probs_dict = {action_classes[i] if i < len(action_classes) else f"act_{i}": round(float(p), 4) for i, p in enumerate(probabilities)}
    else:
        pred_label = f"Class {pred_class}"
        pred_tier = "CLASSIFICATION"
        probs_dict = {f"class_{i}": round(float(p), 4) for i, p in enumerate(probabilities)}

    # Explainability: Compute Local Feature Contributions
    feature_contributions = []
    if hasattr(model, "feature_importances_"):
        deviations = np.abs(X_scaled[0])
        importances = model.feature_importances_
        impacts = deviations * importances
        total_impact = np.sum(impacts) + 1e-7
        norm_impacts = impacts / total_impact

        for f_name, imp, raw_val in zip(feature_cols, norm_impacts, X.iloc[0]):
            feature_contributions.append({
                "feature": f_name,
                "value": round(float(raw_val), 3),
                "contribution_pct": round(float(imp) * 100, 2),
                "direction": "ELEVATING" if pred_class > 0 else "NORMALIZING"
            })
    elif hasattr(model, "coef_"):
        coefs = model.coef_[pred_class] if len(model.coef_.shape) > 1 else model.coef_
        logits = coefs * X_scaled[0]
        for f_name, logit, raw_val in zip(feature_cols, logits, X.iloc[0]):
            feature_contributions.append({
                "feature": f_name,
                "value": round(float(raw_val), 3),
                "contribution_score": round(float(logit), 4),
                "direction": "ELEVATING" if logit > 0 else "NORMALIZING"
            })

    feature_contributions = sorted(feature_contributions, key=lambda x: abs(x.get("contribution_pct", x.get("contribution_score", 0))), reverse=True)

    latency_ms = round((time.time() - start_time) * 1000, 2)
    pred_uuid = f"pred_{hashlib.md5(f'{time.time()}_{random.random()}'.encode()).hexdigest()[:12]}"

    result = {
        "prediction_uuid": pred_uuid,
        "predicted_class": pred_class,
        "predicted_tier": pred_tier,
        "predicted_label": pred_label,
        "confidence": round(confidence, 4),
        "probabilities": probs_dict,
        "model_id": bundle["model_id"],
        "model_version": bundle.get("version", "v1.0.0"),
        "algorithm": bundle.get("algorithm", "ML"),
        "latency_ms": latency_ms,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "validation_warnings": validation_warnings,
        "explanation": {
            "top_features": feature_contributions[:6],
            "all_features": feature_contributions
        }
    }

    # Store prediction into database audit log
    conn = get_db_connection(db_path)
    try:
        with conn:
            conn.execute("""
                INSERT INTO predictions (
                    prediction_uuid, model_id, model_version, source,
                    input_features_json, predicted_class, predicted_tier,
                    predicted_label, confidence, probabilities_json,
                    explanation_json, latency_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                pred_uuid, bundle["model_id"], bundle.get("version", "v1.0.0"), source,
                json.dumps(sanitized_input), pred_class, pred_tier,
                pred_label, confidence, json.dumps(result["probabilities"]),
                json.dumps(result["explanation"]), latency_ms
            ))
    except Exception as e:
        print(f"[PREDICTION LOG WARNING] Could not persist prediction to DB: {e}", file=sys.stderr)
    finally:
        conn.close()

    return result


# =============================================================================
# 7. CLI / SUBPROCESS RPC INTERFACE
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="CIRIS Wearable Production Data & ML Engine")
    parser.add_argument("--action", required=True, choices=["ingest", "validate", "eda", "train", "predict", "list_models", "activate_model"])
    parser.add_argument("--dataset-id", type=str, default=None)
    parser.add_argument("--file-path", type=str, default=None)
    parser.add_argument("--dataset-name", type=str, default=None)
    parser.add_argument("--algorithm", type=str, default="random_forest")
    parser.add_argument("--model-id", type=str, default=None)
    parser.add_argument("--input-json", type=str, default=None)
    parser.add_argument("--db-path", type=str, default=DEFAULT_DB_PATH)

    args = parser.parse_args()

    try:
        if args.action == "ingest":
            res = ingest_dataset_file(args.file_path, args.dataset_name, args.db_path)
            print(json.dumps({"success": True, "data": res}))

        elif args.action == "validate":
            res = validate_and_load_dataset(args.dataset_id, args.file_path, args.db_path)
            print(json.dumps({"success": True, "data": res}))

        elif args.action == "eda":
            res = compute_and_cache_eda(args.dataset_id, args.file_path, args.db_path)
            print(json.dumps({"success": True, "data": res}))

        elif args.action == "train":
            res = train_and_register_model(args.dataset_id, args.file_path, args.algorithm, db_path=args.db_path)
            print(json.dumps({"success": True, "data": res}))

        elif args.action == "predict":
            input_dict = json.loads(args.input_json) if args.input_json else {}
            res = predict_single_sample(input_dict, model_id=args.model_id, db_path=args.db_path)
            print(json.dumps({"success": True, "data": res}))

        elif args.action == "list_models":
            conn = get_db_connection(args.db_path)
            models = conn.execute("SELECT * FROM models ORDER BY trained_at DESC").fetchall()
            conn.close()
            print(json.dumps({"success": True, "data": [dict(m) for m in models]}))

        elif args.action == "activate_model":
            conn = get_db_connection(args.db_path)
            with conn:
                conn.execute("UPDATE models SET is_active = 0")
                conn.execute("UPDATE models SET is_active = 1, status = 'production' WHERE model_id = ?", (args.model_id,))
            conn.close()
            print(json.dumps({"success": True, "message": f"Model {args.model_id} activated as production model"}))

    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
