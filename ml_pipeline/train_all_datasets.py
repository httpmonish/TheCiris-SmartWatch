"""
==============================================================================
CIRIS WEARABLE UNIFIED MULTI-DATASET ML TRAINER & REGISTRY ORCHESTRATOR
==============================================================================
Orchestrates:
  1. CIRIS Multi-Modal Wearable Biosensor Dataset (100k scale)
  2. WISDM Smartwatch Motion Dataset (51 subjects, 18 activities)
  3. Kaggle Human Action Recognition (HAR) Multimodal Vision Dataset (15 classes)
"""

import os
import sys
import time
import json
import sqlite3

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(BASE_DIR, "ml_pipeline"))

from pipeline_engine import (
    ingest_dataset_file, validate_and_load_dataset,
    compute_and_cache_eda, train_and_register_model, DEFAULT_DB_PATH
)
from wisdm_smartwatch_har import (
    process_wisdm_raw_files, register_wisdm_dataset_in_db, train_wisdm_model
)
from kaggle_har_processor import (
    process_kaggle_har_dataset, register_kaggle_dataset_in_db, train_kaggle_har_model
)

DATA_DIR = os.path.join(BASE_DIR, "ml_pipeline", "data")
MODELS_DIR = os.path.join(BASE_DIR, "ml_pipeline", "models")


def main():
    print("=" * 80)
    print("CIRIS PRODUCTION MULTI-DATASET ML TRAINING BENCH")
    print("=" * 80)
    
    start_all = time.time()
    results = {}

    # 1. CIRIS Multi-Modal Wearable Biosensor Dataset
    print("\n[1/3] Processing CIRIS Wearable 100k Biosensor Dataset...")
    wearable_csv = os.path.join(DATA_DIR, "wearable_100k_dataset.csv")
    if not os.path.exists(wearable_csv):
        print(f"Generating synthetic wearable dataset at {wearable_csv}...")
        from generate_synthetic_dataset import generate_1_lakh_dataset
        df_ciris, _ = generate_1_lakh_dataset(wearable_csv)
    
    ingest_meta = ingest_dataset_file(wearable_csv, dataset_name="CIRIS Multi-Modal 100k Wearable")
    ds_id = ingest_meta["dataset_id"]
    val_meta = validate_and_load_dataset(ds_id, wearable_csv)
    eda_meta = compute_and_cache_eda(ds_id, wearable_csv)
    ciris_model = train_and_register_model(ds_id, wearable_csv, algorithm="random_forest")
    results["ciris_biosensor"] = {
        "dataset_id": ds_id,
        "quality_score": val_meta["quality_score"],
        "accuracy": ciris_model["accuracy"],
        "f1": ciris_model["f1"]
    }
    print(f"  -> CIRIS Model Trained. Accuracy: {ciris_model['accuracy']:.4f}, F1: {ciris_model['f1']:.4f}")

    # 2. WISDM Smartwatch Motion Dataset
    print("\n[2/3] Processing WISDM Smartwatch Motion HAR Dataset...")
    wisdm_csv = os.path.join(DATA_DIR, "wisdm_smartwatch_har.csv")
    if not os.path.exists(wisdm_csv) or os.path.getsize(wisdm_csv) < 1000:
        print("  Extracting raw smartwatch IMU window features...")
        df_wisdm = process_wisdm_raw_files(max_subjects=35)
    
    reg_wisdm = register_wisdm_dataset_in_db(wisdm_csv)
    wisdm_rf = train_wisdm_model(wisdm_csv, algorithm="random_forest")
    results["wisdm_smartwatch_har"] = {
        "dataset_id": "ds_wisdm_smartwatch_har",
        "accuracy": wisdm_rf["accuracy"],
        "f1": wisdm_rf["f1"]
    }
    print(f"  -> WISDM Model Trained. Accuracy: {wisdm_rf['accuracy']:.4f}, F1: {wisdm_rf['f1']:.4f}")

    # 3. Kaggle Human Action Recognition (HAR) Dataset
    print("\n[3/3] Processing Kaggle Human Action Recognition Vision Dataset...")
    kaggle_csv = os.path.join(DATA_DIR, "kaggle_har_dataset.csv")
    if not os.path.exists(kaggle_csv) or os.path.getsize(kaggle_csv) < 1000:
        print("  Extracting computer vision spatial & gradient descriptors...")
        df_kaggle = process_kaggle_har_dataset(max_samples=2500)

    reg_kaggle = register_kaggle_dataset_in_db(kaggle_csv)
    kaggle_rf = train_kaggle_har_model(kaggle_csv, algorithm="random_forest")
    results["kaggle_har"] = {
        "dataset_id": "ds_kaggle_human_action_rec",
        "accuracy": kaggle_rf["accuracy"],
        "f1": kaggle_rf["f1"]
    }
    print(f"  -> Kaggle HAR Model Trained. Accuracy: {kaggle_rf['accuracy']:.4f}, F1: {kaggle_rf['f1']:.4f}")

    elapsed = round(time.time() - start_all, 2)
    print("\n" + "=" * 80)
    print(f"ALL 3 DATASETS PROCESSED & TRAINED IN {elapsed} SECONDS!")
    print("=" * 80)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
