"""
==============================================================================
CIRIS WEARABLE PRODUCTION TEST FIXTURES & SEED DATASET GENERATOR
==============================================================================
Generates test fixture datasets matching Requirement 7:
  - empty_dataset.csv
  - small_dataset.csv (10 rows)
  - normal_dataset.csv (500 rows)
  - duplicate_heavy_dataset.csv (100 rows with 60% duplicates)
  - missing_value_dataset.csv (100 rows with null values)
  - malformed_dataset.csv (100 rows with out-of-bounds physical spikes)
  - edge_case_dataset.csv (boundary values: max HR 220, SpO2 65%, extreme temp -10°C, high jerk)
==============================================================================
"""

import os
import csv
import random
import pandas as pd
import numpy as np

FIXTURES_DIR = os.path.dirname(os.path.abspath(__file__))

HEADER = [
    "sample_id", "scenario_tag", "heart_rate_bpm", "rmssd_ms", "spo2_pct",
    "skin_temp_c", "ambient_temp_c", "ambient_humidity_pct", "imu_jerk_ms3",
    "aqi_ppm", "barometric_pressure_hpa", "flood_threat_index", "risk_class", "risk_tier"
]

def make_sample(i, hr=72.0, rmssd=45.0, spo2=98.4, skin=34.2, amb_t=24.6, hum=48.2, jerk=0.8, aqi=35.0, p=1013.2, flood=0.04, label=0, tier="NOMINAL_GREEN", tag="Normal Baseline"):
    return [i, tag, hr, rmssd, spo2, skin, amb_t, hum, jerk, aqi, p, flood, label, tier]

def generate_all_fixtures():
    os.makedirs(FIXTURES_DIR, exist_ok=True)

    # 1. Empty Dataset
    with open(os.path.join(FIXTURES_DIR, "empty_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)

    # 2. Small Dataset (10 rows)
    rows_small = [make_sample(i, hr=70+i*2, spo2=98.0, label=0) for i in range(1, 11)]
    with open(os.path.join(FIXTURES_DIR, "small_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_small)

    # 3. Normal Dataset (500 rows)
    rows_normal = []
    for i in range(1, 501):
        if i <= 300:
            rows_normal.append(make_sample(i, hr=round(random.gauss(72, 6), 1), rmssd=round(random.gauss(48, 8), 1), spo2=round(random.gauss(98.4, 0.6), 1), label=0, tier="NOMINAL_GREEN", tag="Normal Baseline"))
        elif i <= 400:
            rows_normal.append(make_sample(i, hr=round(random.gauss(120, 10), 1), rmssd=round(random.gauss(18, 4), 1), amb_t=round(random.gauss(42, 2), 1), label=1, tier="WARNING_ORANGE", tag="Heat Wave"))
        else:
            rows_normal.append(make_sample(i, hr=round(random.gauss(135, 12), 1), rmssd=round(random.gauss(12, 3), 1), flood=round(random.uniform(0.8, 0.98), 3), label=2, tier="CRITICAL_RED", tag="Flash Flood"))
    with open(os.path.join(FIXTURES_DIR, "normal_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_normal)

    # 4. Duplicate-Heavy Dataset (100 rows with identical repeating entries)
    base_row = make_sample(1, hr=75.0, rmssd=40.0, spo2=98.0, label=0)
    rows_dup = [base_row.copy() for _ in range(70)] + [make_sample(i, hr=120.0, label=1) for i in range(71, 101)]
    with open(os.path.join(FIXTURES_DIR, "duplicate_heavy_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_dup)

    # 5. Missing-Value Dataset (Null / None entries in features)
    rows_missing = []
    for i in range(1, 101):
        r = make_sample(i, label=0)
        if i % 4 == 0:
            r[2] = "" # missing HR
        if i % 7 == 0:
            r[4] = "" # missing SpO2
        rows_missing.append(r)
    with open(os.path.join(FIXTURES_DIR, "missing_value_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_missing)

    # 6. Malformed Dataset (Out-of-bound sensor violations, e.g. HR=999, SpO2=-50)
    rows_malformed = []
    for i in range(1, 101):
        if i <= 30:
            rows_malformed.append(make_sample(i, hr=850.0, spo2=150.0, skin=95.0, label=0, tag="Sensor Malfunction / Glitch"))
        else:
            rows_malformed.append(make_sample(i, hr=72.0, spo2=98.0, label=0))
    with open(os.path.join(FIXTURES_DIR, "malformed_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_malformed)

    # 7. Edge-Case Dataset (Physical extremes: near-freezing -10°C, altitude 3000m pressure 700 hPa, max HR 220, max jerk 55 m/s³)
    rows_edge = [
        make_sample(1, hr=220.0, rmssd=3.0, spo2=89.0, label=2, tier="CRITICAL_RED", tag="Extreme Tachycardia"),
        make_sample(2, hr=32.0, rmssd=4.0, spo2=86.0, label=2, tier="CRITICAL_RED", tag="Extreme Bradycardia"),
        make_sample(3, amb_t=-10.0, skin=28.5, label=0, tier="NOMINAL_GREEN", tag="Sub-Zero Cold Climate"),
        make_sample(4, amb_t=52.0, hum=90.0, skin=41.5, label=2, tier="CRITICAL_RED", tag="Extreme Heat Stroke"),
        make_sample(5, p=680.0, spo2=91.0, label=1, tier="CAUTION_YELLOW", tag="High Altitude Low Pressure"),
        make_sample(6, jerk=52.0, hr=160.0, label=2, tier="CRITICAL_RED", tag="Severe G-Impact Fall"),
        make_sample(7, aqi=480.0, hr=115.0, label=1, tier="WARNING_ORANGE", tag="Hazardous AQI Smog"),
        make_sample(8, flood=0.99, hum=99.0, p=940.0, label=2, tier="CRITICAL_RED", tag="Extreme Flood / Cyclone"),
    ]
    with open(os.path.join(FIXTURES_DIR, "edge_case_dataset.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows_edge)

    print("[FIXTURES] All 7 test dataset fixtures successfully generated in:", FIXTURES_DIR)

if __name__ == "__main__":
    generate_all_fixtures()
