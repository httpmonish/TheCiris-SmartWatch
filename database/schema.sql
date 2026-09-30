-- ==============================================================================
-- CIRIS WEARABLE PRODUCTION DATABASE SCHEMA
-- Relational Schema for Data Ingestion, Validation, EDA, ML Registry & Predictions
-- ==============================================================================

-- 1. Schema Migrations Tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Versioned Datasets Registry
CREATE TABLE IF NOT EXISTS datasets (
    dataset_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    file_format TEXT NOT NULL CHECK (file_format IN ('csv', 'json', 'parquet', 'synthetic')),
    file_size_bytes INTEGER NOT NULL DEFAULT 0,
    checksum_sha256 TEXT,
    row_count INTEGER NOT NULL DEFAULT 0,
    column_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'UPLOADED' CHECK (status IN ('UPLOADED', 'VALIDATING', 'VALIDATED', 'CLEANING', 'PROCESSED', 'ANALYZED', 'FAILED')),
    error_message TEXT,
    metadata_json TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Normalized Ingested Dataset Records
CREATE TABLE IF NOT EXISTS dataset_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_id TEXT NOT NULL,
    sample_id INTEGER NOT NULL,
    scenario_tag TEXT,
    heart_rate_bpm REAL NOT NULL CHECK (heart_rate_bpm >= 20.0 AND heart_rate_bpm <= 250.0),
    rmssd_ms REAL NOT NULL CHECK (rmssd_ms >= 0.0 AND rmssd_ms <= 300.0),
    spo2_pct REAL NOT NULL CHECK (spo2_pct >= 50.0 AND spo2_pct <= 100.0),
    skin_temp_c REAL NOT NULL CHECK (skin_temp_c >= 20.0 AND skin_temp_c <= 50.0),
    ambient_temp_c REAL NOT NULL CHECK (ambient_temp_c >= -40.0 AND ambient_temp_c <= 70.0),
    ambient_humidity_pct REAL NOT NULL CHECK (ambient_humidity_pct >= 0.0 AND ambient_humidity_pct <= 100.0),
    imu_jerk_ms3 REAL NOT NULL CHECK (imu_jerk_ms3 >= 0.0),
    aqi_ppm REAL NOT NULL CHECK (aqi_ppm >= 0.0),
    barometric_pressure_hpa REAL NOT NULL CHECK (barometric_pressure_hpa >= 500.0 AND barometric_pressure_hpa <= 1200.0),
    flood_threat_index REAL NOT NULL CHECK (flood_threat_index >= 0.0 AND flood_threat_index <= 1.0),
    risk_class INTEGER NOT NULL CHECK (risk_class IN (0, 1, 2)),
    risk_tier TEXT NOT NULL CHECK (risk_tier IN ('NOMINAL_GREEN', 'CAUTION_YELLOW', 'WARNING_ORANGE', 'CRITICAL_RED')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dataset_id) REFERENCES datasets(dataset_id) ON DELETE CASCADE
);

-- Indexes for high-throughput filtering and analytics
CREATE INDEX IF NOT EXISTS idx_records_dataset_id ON dataset_records(dataset_id);
CREATE INDEX IF NOT EXISTS idx_records_risk_class ON dataset_records(risk_class);
CREATE INDEX IF NOT EXISTS idx_records_scenario ON dataset_records(scenario_tag);
CREATE INDEX IF NOT EXISTS idx_records_vitals ON dataset_records(heart_rate_bpm, spo2_pct);

-- 4. Ingestion & Data Quality Validation Reports
CREATE TABLE IF NOT EXISTS validation_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('PASS', 'WARNING', 'FAIL')),
    total_rows INTEGER NOT NULL DEFAULT 0,
    valid_rows INTEGER NOT NULL DEFAULT 0,
    invalid_rows INTEGER NOT NULL DEFAULT 0,
    duplicate_rows INTEGER NOT NULL DEFAULT 0,
    missing_values_count INTEGER NOT NULL DEFAULT 0,
    quality_score REAL NOT NULL DEFAULT 100.0,
    validation_duration_ms INTEGER NOT NULL DEFAULT 0,
    report_json TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dataset_id) REFERENCES datasets(dataset_id) ON DELETE CASCADE
);

-- 5. Rejected / Malformed Records Audit Table
CREATE TABLE IF NOT EXISTS validation_errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_id TEXT NOT NULL,
    row_index INTEGER NOT NULL,
    field_name TEXT NOT NULL,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    raw_value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dataset_id) REFERENCES datasets(dataset_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_val_errors_dataset ON validation_errors(dataset_id);

-- 6. Exploratory Data Analysis (EDA) Cache
CREATE TABLE IF NOT EXISTS eda_analytics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_id TEXT NOT NULL UNIQUE,
    summary_stats_json TEXT NOT NULL,
    correlations_json TEXT NOT NULL,
    distributions_json TEXT NOT NULL,
    class_distribution_json TEXT NOT NULL,
    scenario_distribution_json TEXT NOT NULL,
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dataset_id) REFERENCES datasets(dataset_id) ON DELETE CASCADE
);

-- 7. Machine Learning Model Registry
CREATE TABLE IF NOT EXISTS models (
    model_id TEXT PRIMARY KEY,
    model_name TEXT NOT NULL,
    version TEXT NOT NULL,
    algorithm TEXT NOT NULL,
    training_dataset_id TEXT NOT NULL,
    target_column TEXT NOT NULL DEFAULT 'risk_class',
    feature_names_json TEXT NOT NULL,
    feature_preprocessing_json TEXT NOT NULL,
    hyperparameters_json TEXT NOT NULL,
    metrics_json TEXT NOT NULL,
    confusion_matrix_json TEXT NOT NULL,
    artifact_path TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'staging' CHECK (status IN ('development', 'staging', 'production', 'archived')),
    is_active INTEGER NOT NULL DEFAULT 0,
    trained_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (training_dataset_id) REFERENCES datasets(dataset_id)
);

CREATE INDEX IF NOT EXISTS idx_models_status ON models(status, is_active);

-- 8. Predictions Audit & Explainability Store
CREATE TABLE IF NOT EXISTS predictions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    prediction_uuid TEXT NOT NULL UNIQUE,
    model_id TEXT NOT NULL,
    model_version TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'API_REQUEST' CHECK (source IN ('API_REQUEST', 'LIVE_TELEMETRY', 'BATCH_JOB', 'SIMULATOR')),
    input_features_json TEXT NOT NULL,
    predicted_class INTEGER NOT NULL,
    predicted_tier TEXT NOT NULL,
    predicted_label TEXT NOT NULL,
    confidence REAL NOT NULL,
    probabilities_json TEXT NOT NULL,
    explanation_json TEXT,
    latency_ms REAL NOT NULL DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES models(model_id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_time ON predictions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_predictions_class ON predictions(predicted_class);
CREATE INDEX IF NOT EXISTS idx_predictions_tier ON predictions(predicted_tier);
