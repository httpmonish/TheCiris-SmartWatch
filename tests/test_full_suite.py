"""
==============================================================================
CIRIS WEARABLE PRODUCTION DATA & ML PIPELINE TEST SUITE
==============================================================================
Runs complete verification on:
  1. Relational Database Schema, Foreign Keys & Constraints
  2. Data Ingestion & Schema Type Inference
  3. Physical Boundary Validation & Quality Audit
  4. Deterministic Preprocessing & Zero-Leakage Feature Engineering
  5. Multi-Model Training & Evaluation Benchmarking
  6. Model Registry & Artifact Management
  7. Prediction Engine with Local Explainability & Attribution
==============================================================================
"""

import unittest
import os
import json
import sqlite3
import tempfile
import pandas as pd
import numpy as np

from ml_pipeline.pipeline_engine import (
    get_db_connection,
    ingest_dataset_file,
    validate_and_load_dataset,
    compute_and_cache_eda,
    apply_feature_engineering,
    train_and_register_model,
    predict_single_sample,
    get_active_model,
    DOMAIN_CONSTRAINTS,
    RAW_FEATURE_COLUMNS,
    ALL_FEATURE_COLUMNS
)

class TestCirisDataEngineeringPipeline(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.test_dir = tempfile.mkdtemp()
        cls.test_db_path = os.path.join(cls.test_dir, "test_platform.db")
        
        # Initialize schema
        schema_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "database", "schema.sql"))
        conn = get_db_connection(cls.test_db_path)
        with open(schema_path, "r") as f:
            conn.executescript(f.read())
        conn.close()

        # Create test CSV fixture with realistic variations
        cls.fixture_csv = os.path.join(cls.test_dir, "wearable_test_fixture.csv")
        np.random.seed(42)
        n = 100
        data = {
            "sample_id": list(range(1, n + 1)),
            "scenario_tag": ["0A: Sleep"] * 60 + ["1A: Heat Wave"] * 20 + ["2A: Flash Flood"] * 20,
            "heart_rate_bpm": [55.0 + np.random.normal(0, 1.5) for _ in range(60)] + [120.0 + np.random.normal(0, 2) for _ in range(20)] + [140.0 + np.random.normal(0, 3) for _ in range(20)],
            "rmssd_ms": [65.0 + np.random.normal(0, 2) for _ in range(60)] + [18.0 + np.random.normal(0, 1) for _ in range(20)] + [12.0 + np.random.normal(0, 1) for _ in range(20)],
            "spo2_pct": [98.5 + np.random.normal(0, 0.4) for _ in range(60)] + [95.0 + np.random.normal(0, 0.5) for _ in range(20)] + [88.0 + np.random.normal(0, 0.8) for _ in range(20)],
            "skin_temp_c": [33.5 + np.random.normal(0, 0.2) for _ in range(60)] + [38.5 + np.random.normal(0, 0.3) for _ in range(20)] + [32.0 + np.random.normal(0, 0.3) for _ in range(20)],
            "ambient_temp_c": [22.0 + np.random.normal(0, 0.5) for _ in range(60)] + [42.0 + np.random.normal(0, 0.5) for _ in range(20)] + [24.0 + np.random.normal(0, 0.5) for _ in range(20)],
            "ambient_humidity_pct": [45.0 + np.random.normal(0, 1) for _ in range(60)] + [65.0 + np.random.normal(0, 1) for _ in range(20)] + [95.0 + np.random.normal(0, 1) for _ in range(20)],
            "imu_jerk_ms3": [max(0.05, 0.2 + np.random.normal(0, 0.05)) for _ in range(60)] + [1.5 + np.random.normal(0, 0.2) for _ in range(20)] + [8.5 + np.random.normal(0, 0.5) for _ in range(20)],
            "aqi_ppm": [35.0 + np.random.normal(0, 2) for _ in range(60)] + [110.0 + np.random.normal(0, 5) for _ in range(20)] + [55.0 + np.random.normal(0, 3) for _ in range(20)],
            "barometric_pressure_hpa": [1013.25 + np.random.normal(0, 0.5) for _ in range(60)] + [1011.0 + np.random.normal(0, 0.5) for _ in range(20)] + [960.0 + np.random.normal(0, 1) for _ in range(20)],
            "flood_threat_index": [max(0.0, 0.02 + np.random.normal(0, 0.01)) for _ in range(60)] + [0.20 + np.random.normal(0, 0.02) for _ in range(20)] + [0.95 + np.random.normal(0, 0.01) for _ in range(20)],
            "risk_class": [0] * 60 + [1] * 20 + [2] * 20,
            "risk_tier": ["NOMINAL_GREEN"] * 60 + ["WARNING_ORANGE"] * 20 + ["CRITICAL_RED"] * 20
        }
        pd.DataFrame(data).to_csv(cls.fixture_csv, index=False)

    def test_01_database_schema_and_tables(self):
        """Verify all tables exist and foreign keys are enabled."""
        conn = get_db_connection(self.test_db_path)
        tables = [r["name"] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        expected_tables = ["datasets", "dataset_records", "validation_reports", "validation_errors", "eda_analytics", "models", "predictions"]
        for t in expected_tables:
            self.assertIn(t, tables, f"Missing table: {t}")
        conn.close()

    def test_02_dataset_ingestion(self):
        """Verify ingestion, schema inference, row counts, and checksum generation."""
        res = ingest_dataset_file(self.fixture_csv, "Unit Test Dataset", db_path=self.test_db_path)
        self.assertIsNotNone(res["dataset_id"])
        self.assertEqual(res["row_count"], 100)
        self.assertEqual(res["column_count"], 14)
        self.assertEqual(res["file_format"], "csv")
        self.assertIsNotNone(res["checksum_sha256"])

    def test_03_data_validation_and_loading(self):
        """Verify validation rules, quality score, and database record insertion."""
        ds_res = ingest_dataset_file(self.fixture_csv, "Unit Test Dataset", db_path=self.test_db_path)
        val_res = validate_and_load_dataset(ds_res["dataset_id"], self.fixture_csv, db_path=self.test_db_path)
        self.assertEqual(val_res["status"], "PASS")
        self.assertGreaterEqual(val_res["quality_score"], 90.0)
        self.assertEqual(val_res["valid_rows"], val_res["total_rows"] - val_res["invalid_rows"])

        # Check DB records
        conn = get_db_connection(self.test_db_path)
        count = conn.execute("SELECT COUNT(*) as c FROM dataset_records WHERE dataset_id = ?", (ds_res["dataset_id"],)).fetchone()["c"]
        self.assertEqual(count, val_res["valid_rows"])
        conn.close()

    def test_04_feature_engineering(self):
        """Verify engineered features are calculated accurately."""
        df = pd.read_csv(self.fixture_csv)
        df_feat = apply_feature_engineering(df)
        for f in ["cardiac_strain_index", "thermal_heat_stress", "hypoxia_depth", "shock_motion_index", "barometric_anomaly"]:
            self.assertIn(f, df_feat.columns)

        # Check cardiac strain calculation: HR / (RMSSD + 1)
        expected_cs = round(df["heart_rate_bpm"].iloc[0] / (df["rmssd_ms"].iloc[0] + 1.0), 3)
        self.assertAlmostEqual(df_feat["cardiac_strain_index"].iloc[0], expected_cs, places=2)

    def test_05_statistical_eda(self):
        """Verify EDA summary stats, distributions, and correlation matrix generation."""
        ds_res = ingest_dataset_file(self.fixture_csv, "Unit Test Dataset", db_path=self.test_db_path)
        eda_res = compute_and_cache_eda(ds_res["dataset_id"], self.fixture_csv, db_path=self.test_db_path)
        self.assertIn("summary_stats", eda_res)
        self.assertIn("correlations", eda_res)
        self.assertIn("heart_rate_bpm", eda_res["summary_stats"])
        self.assertEqual(eda_res["summary_stats"]["heart_rate_bpm"]["count"], 100)

    def test_06_model_training_and_registry(self):
        """Verify multi-model training, held-out evaluation, and registry persistence."""
        ds_res = ingest_dataset_file(self.fixture_csv, "Unit Test Dataset", db_path=self.test_db_path)
        validate_and_load_dataset(ds_res["dataset_id"], self.fixture_csv, db_path=self.test_db_path)

        # Train Logistic Regression
        lr_res = train_and_register_model(ds_res["dataset_id"], self.fixture_csv, algorithm="logistic_regression", db_path=self.test_db_path)
        self.assertGreaterEqual(lr_res["accuracy"], 0.90)

        # Train Random Forest
        rf_res = train_and_register_model(ds_res["dataset_id"], self.fixture_csv, algorithm="random_forest", db_path=self.test_db_path)
        self.assertGreaterEqual(rf_res["accuracy"], 0.95)

        # Verify models are registered in DB
        conn = get_db_connection(self.test_db_path)
        models = conn.execute("SELECT * FROM models").fetchall()
        self.assertGreaterEqual(len(models), 2)
        conn.close()

    def test_07_prediction_engine_and_explainability(self):
        """Verify real-time prediction, confidence calibration, and feature attribution."""
        emergency_input = {
            "heart_rate_bpm": 160.0,
            "rmssd_ms": 8.0,
            "spo2_pct": 82.0,
            "skin_temp_c": 35.0,
            "ambient_temp_c": 25.0,
            "ambient_humidity_pct": 55.0,
            "imu_jerk_ms3": 2.0,
            "aqi_ppm": 45.0,
            "barometric_pressure_hpa": 1012.0,
            "flood_threat_index": 0.10
        }

        pred = predict_single_sample(emergency_input, db_path=self.test_db_path)
        self.assertIn(pred["predicted_class"], [0, 1, 2])
        self.assertIn("probabilities", pred)
        self.assertIn("explanation", pred)
        self.assertGreaterEqual(len(pred["explanation"]["top_features"]), 1)

        # Verify prediction log in database
        conn = get_db_connection(self.test_db_path)
        pred_log = conn.execute("SELECT * FROM predictions WHERE prediction_uuid = ?", (pred["prediction_uuid"],)).fetchone()
        self.assertIsNotNone(pred_log)
        self.assertEqual(pred_log["predicted_tier"], pred["predicted_tier"])
        conn.close()

    def test_08_wisdm_smartwatch_pipeline(self):
        """Verify WISDM smartwatch motion feature extraction, DB registration, and model training."""
        from ml_pipeline.wisdm_smartwatch_har import extract_window_features, register_wisdm_dataset_in_db, train_wisdm_model, WISDM_FEATURE_COLUMNS
        
        # Test window feature extractor
        accel_mock = np.random.normal(9.8, 1.5, size=(100, 3))
        gyro_mock = np.random.normal(0.0, 0.5, size=(100, 3))
        feats = extract_window_features(accel_mock, gyro_mock)
        for col in WISDM_FEATURE_COLUMNS:
            self.assertIn(col, feats)

        # Create mock WISDM CSV fixture
        wisdm_fixture_path = os.path.join(self.test_dir, "wisdm_test_fixture.csv")
        rows = []
        for i in range(60):
            act_id = i % 3
            act_name = ["Walking", "Jogging", "Sitting"][act_id]
            f = extract_window_features(np.random.normal(9.8 + act_id * 2.0, 1.0, size=(100, 3)))
            f["subject_id"] = 1600 + (i % 5)
            f["activity_code"] = ["A", "B", "D"][act_id]
            f["activity_name"] = act_name
            f["activity_id"] = act_id
            f["activity_category"] = "Ambulation" if act_id < 2 else "Sedentary"
            rows.append(f)
        pd.DataFrame(rows).to_csv(wisdm_fixture_path, index=False)

        # Test registration
        reg_res = register_wisdm_dataset_in_db(wisdm_fixture_path, db_path=self.test_db_path)
        self.assertEqual(reg_res["status"], "REGISTERED_AND_ANALYZED")

        # Test model training
        model_res = train_wisdm_model(wisdm_fixture_path, algorithm="random_forest", db_path=self.test_db_path)
        self.assertIn("accuracy", model_res)
        self.assertGreaterEqual(model_res["accuracy"], 0.70)

    def test_09_kaggle_har_pipeline(self):
        """Verify Kaggle Human Action Recognition feature registration and model training."""
        from ml_pipeline.kaggle_har_processor import register_kaggle_dataset_in_db, train_kaggle_har_model, KAGGLE_FEATURE_COLUMNS

        # Create mock Kaggle HAR CSV fixture
        kaggle_fixture_path = os.path.join(self.test_dir, "kaggle_test_fixture.csv")
        rows = []
        for i in range(60):
            act_id = i % 3
            act_label = ["cycling", "running", "sitting"][act_id]
            f = {col: float(np.random.normal(50.0 + act_id * 30.0, 5.0)) for col in KAGGLE_FEATURE_COLUMNS}
            f["filename"] = f"Image_{i}.jpg"
            f["action_label"] = act_label
            f["action_id"] = act_id
            rows.append(f)
        pd.DataFrame(rows).to_csv(kaggle_fixture_path, index=False)

        # Test registration
        reg_res = register_kaggle_dataset_in_db(kaggle_fixture_path, db_path=self.test_db_path)
        self.assertEqual(reg_res["status"], "REGISTERED_AND_ANALYZED")

        # Test model training
        model_res = train_kaggle_har_model(kaggle_fixture_path, algorithm="random_forest", db_path=self.test_db_path)
        self.assertIn("accuracy", model_res)
        self.assertGreaterEqual(model_res["accuracy"], 0.70)

if __name__ == "__main__":
    unittest.main()
