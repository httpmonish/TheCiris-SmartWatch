import random
import math
import json
import csv
import os
import time

def extract_features_from_raw_windows(ppg_peaks, raw_accel, dt_sec=0.02):
    """
    DSP feature extraction from raw peak timestamps (ms) and raw 3-axis accelerometer buffers.
    Computes Heart Rate (BPM), RMSSD (ms), and RMS Jerk (m/s^3).
    """
    # 1. Heart Rate & RMSSD from peak-to-peak intervals
    if len(ppg_peaks) < 2:
        hr = 70.0
        rmssd = 35.0
    else:
        ibis = [ppg_peaks[i] - ppg_peaks[i - 1] for i in range(1, len(ppg_peaks))]
        mean_ibi = sum(ibis) / len(ibis)
        hr = 60000.0 / mean_ibi if mean_ibi > 0 else 70.0
        
        if len(ibis) > 1:
            diffs = [(ibis[i] - ibis[i - 1]) ** 2 for i in range(1, len(ibis))]
            rmssd = math.sqrt(sum(diffs) / len(diffs))
        else:
            rmssd = 30.0

    # 2. IMU RMS Jerk: derivative of acceleration magnitude over time dt_sec
    if len(raw_accel) < 2:
        jerk_rms = 1.0
    else:
        mags = [math.sqrt(ax**2 + ay**2 + az**2) for ax, ay, az in raw_accel]
        jerks = [abs(mags[i] - mags[i - 1]) / dt_sec for i in range(1, len(mags))]
        jerk_rms = math.sqrt(sum(j**2 for j in jerks) / len(jerks)) if jerks else 1.0

    return hr, rmssd, jerk_rms


"""
=============================================================================
5 MILLION (5,000,000 ROWS) CSV & JSON MULTI-MODAL DATASET GENERATOR
=============================================================================
Exports:
  1. ml_pipeline/data/wearable_5M_dataset.csv (5,000,000 rows streaming export)
  2. ml_pipeline/data/wearable_100k_dataset.csv (100,000 rows for quick validation)
  3. ml_pipeline/data/synthetic_dataset.json (Compact metadata & training splits)

Columns (14 Columns):
  [0] sample_id
  [1] scenario_tag
  [2] heart_rate_bpm
  [3] rmssd_ms
  [4] spo2_pct
  [5] skin_temp_c
  [6] ambient_temp_c
  [7] ambient_humidity_pct
  [8] imu_jerk_ms3
  [9] aqi_ppm
  [10] barometric_pressure_hpa
  [11] flood_threat_index
  [12] risk_class (0=Normal, 1=Strain, 2=Emergency/Flood)
  [13] risk_tier (NOMINAL, CAUTION, WARNING, CRITICAL)
"""

def generate_sample(sample_id, base_pressure=1013.25):
    """Generates a single multi-modal sample with realistic physiologic & environmental noise."""
    r = random.random()
    
    noise_spo2 = random.gauss(0, 0.6)
    noise_temp = random.gauss(0, 0.25)
    noise_hum = random.gauss(0, 1.5)
    noise_aqi = random.gauss(0, 5.0)

    # ====================================================================
    # CLASS 0: NORMAL BASELINE & ROUTINE SAFE ACTIVITIES (62%)
    # ====================================================================
    if r < 0.62:
        sub = random.random()
        if sub < 0.20:
            tag = "0A: Sleep/Deep Rest"
            hr = random.gauss(54, 4)
            rmssd = random.gauss(68, 10)
            jerk = max(0.05, random.gauss(0.15, 0.08))
            spo2 = random.gauss(98.2, 0.8) + noise_spo2
            skin_temp = random.gauss(33.5, 0.4) + noise_temp
            amb_temp = random.gauss(22.0, 2.0)
            amb_hum = random.gauss(45.0, 4.0) + noise_hum
            aqi = max(10.0, random.gauss(42.0, 12.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.08)
        elif sub < 0.50:
            tag = "0B: Sedentary/Desk"
            hr = random.gauss(72, 6)
            rmssd = random.gauss(48, 8)
            jerk = max(0.1, random.gauss(0.8, 0.3))
            spo2 = random.gauss(98.5, 0.7) + noise_spo2
            skin_temp = random.gauss(34.2, 0.5) + noise_temp
            amb_temp = random.gauss(25.0, 2.5)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(15.0, random.gauss(65.0, 15.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.12)
        elif sub < 0.75:
            tag = "0C: Walking/Commute"
            hr = random.gauss(94, 8)
            rmssd = random.gauss(36, 6)
            jerk = max(1.2, random.gauss(3.5, 1.0))
            spo2 = random.gauss(98.0, 0.8) + noise_spo2
            skin_temp = random.gauss(34.8, 0.5) + noise_temp
            amb_temp = random.gauss(27.0, 3.0)
            amb_hum = random.gauss(55.0, 6.0) + noise_hum
            aqi = max(20.0, random.gauss(85.0, 20.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.5)
            flood_risk = random.uniform(0.0, 0.15)
        elif sub < 0.90:
            tag = "0D: Heavy Labor/Workout"
            hr = random.gauss(142, 12)
            rmssd = random.gauss(22, 5)
            jerk = max(4.5, random.gauss(16.0, 4.0))
            spo2 = random.gauss(97.0, 1.0) + noise_spo2
            skin_temp = random.gauss(35.8, 0.7) + noise_temp
            amb_temp = random.gauss(28.5, 3.5)
            amb_hum = random.gauss(60.0, 7.0) + noise_hum
            aqi = max(20.0, random.gauss(75.0, 18.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.5)
            flood_risk = random.uniform(0.0, 0.12)
        elif sub < 0.96:
            tag = "0E: Cold Climate"
            hr = random.gauss(68, 6)
            rmssd = random.gauss(52, 8)
            jerk = max(0.2, random.gauss(1.2, 0.5))
            spo2 = random.gauss(98.2, 0.8) + noise_spo2
            skin_temp = random.gauss(30.8, 0.8) + noise_temp
            amb_temp = random.gauss(11.0, 3.0)
            amb_hum = random.gauss(40.0, 5.0) + noise_hum
            aqi = max(10.0, random.gauss(45.0, 15.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.08)
        else:
            tag = "0F: High Altitude Baseline (3000m)"
            hr = random.gauss(82, 7)
            rmssd = random.gauss(40, 7)
            jerk = max(0.3, random.gauss(1.5, 0.6))
            spo2 = random.gauss(95.5, 1.0) + noise_spo2
            skin_temp = random.gauss(32.5, 0.6) + noise_temp
            amb_temp = random.gauss(14.0, 4.0)
            amb_hum = random.gauss(35.0, 6.0) + noise_hum
            aqi = max(10.0, random.gauss(30.0, 10.0) + noise_aqi)
            pressure = 700.0 + random.gauss(0, 15.0)
            flood_risk = random.uniform(0.0, 0.05)
        label = 0
        tier = "NOMINAL_GREEN"

    # ====================================================================
    # CLASS 1: EARLY WARNING — ENVIRONMENTAL & HEAT STRAIN (20%)
    # ====================================================================
    elif r < 0.82:
        sub = random.random()
        if sub < 0.28:
            tag = "1A: Heat Wave Strain"
            hr = random.gauss(122, 10)
            rmssd = random.gauss(18, 4)
            jerk = max(0.2, random.gauss(2.2, 1.0))
            spo2 = random.gauss(95.2, 1.2) + noise_spo2
            skin_temp = random.gauss(38.4, 0.6) + noise_temp
            amb_temp = random.gauss(41.0, 2.5)
            amb_hum = random.gauss(65.0, 6.0) + noise_hum
            aqi = max(40.0, random.gauss(110.0, 25.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.10, 0.30)
            tier = "WARNING_ORANGE"
        elif sub < 0.52:
            tag = "1B: Toxic Air Pollution"
            hr = random.gauss(106, 9)
            rmssd = random.gauss(22, 5)
            jerk = max(0.1, random.gauss(1.0, 0.5))
            spo2 = random.gauss(94.5, 1.4) + noise_spo2
            skin_temp = random.gauss(34.6, 0.5) + noise_temp
            amb_temp = random.gauss(28.0, 3.0)
            amb_hum = random.gauss(55.0, 5.0) + noise_hum
            aqi = max(220.0, random.gauss(320.0, 45.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.05, 0.25)
            tier = "WARNING_ORANGE"
        elif sub < 0.72:
            tag = "1C: Moderate Hypoxia (90-94%)"
            hr = random.gauss(105, 9)
            rmssd = random.gauss(24, 5)
            jerk = max(0.1, random.gauss(1.1, 0.5))
            spo2 = random.gauss(92.2, 1.0) + noise_spo2
            skin_temp = random.gauss(34.0, 0.5) + noise_temp
            amb_temp = random.gauss(24.0, 2.5)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(20.0, random.gauss(70.0, 15.0) + noise_aqi)
            pressure = base_pressure - random.gauss(40.0, 8.0)
            flood_risk = random.uniform(0.10, 0.30)
            tier = "CAUTION_YELLOW"
        elif sub < 0.88:
            tag = "1D: Acute Sympathetic Stress"
            hr = random.gauss(116, 9)
            rmssd = random.gauss(15, 3)
            jerk = max(0.1, random.gauss(0.8, 0.3))
            spo2 = random.gauss(97.2, 0.9) + noise_spo2
            skin_temp = random.gauss(34.6, 0.5) + noise_temp
            amb_temp = random.gauss(26.0, 2.5)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(20.0, random.gauss(65.0, 15.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.05, 0.20)
            tier = "CAUTION_YELLOW"
        else:
            tag = "1E: Febrile Infection / Pre-Heat Stroke"
            hr = random.gauss(110, 8)
            rmssd = random.gauss(20, 4)
            jerk = max(0.05, random.gauss(0.5, 0.2))
            spo2 = random.gauss(95.8, 1.0) + noise_spo2
            skin_temp = random.gauss(38.4, 0.5) + noise_temp
            amb_temp = random.gauss(32.0, 3.0)
            amb_hum = random.gauss(60.0, 6.0) + noise_hum
            aqi = max(15.0, random.gauss(55.0, 12.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.05, 0.20)
            tier = "CAUTION_YELLOW"
        label = 1

    # ====================================================================
    # CLASS 2: CRITICAL LIFE EMERGENCIES & DISASTER THREATS (18%)
    # ====================================================================
    else:
        sub = random.random()
        if sub < 0.22:
            tag = "2A: Flash Flood Hazard"
            hr = random.gauss(130, 14)
            rmssd = random.gauss(16, 4)
            jerk = max(1.0, random.gauss(5.5, 2.0))
            spo2 = random.gauss(95.0, 1.2) + noise_spo2
            skin_temp = random.gauss(31.5, 1.0) + noise_temp
            amb_temp = random.gauss(24.0, 2.0)
            amb_hum = random.gauss(95.0, 3.0) + noise_hum
            aqi = max(20.0, random.gauss(60.0, 15.0) + noise_aqi)
            pressure = base_pressure + random.gauss(2.5, 0.8)
            flood_risk = random.uniform(0.85, 1.00)
        elif sub < 0.42:
            tag = "2B: Resting Tachycardia"
            hr = random.gauss(165, 14)
            rmssd = random.gauss(11, 3)
            jerk = max(0.05, random.gauss(0.6, 0.3))
            spo2 = random.gauss(94.2, 1.2) + noise_spo2
            skin_temp = random.gauss(35.2, 0.6) + noise_temp
            amb_temp = random.gauss(24.0, 2.0)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(15.0, random.gauss(50.0, 12.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.15)
        elif sub < 0.60:
            tag = "2C: Severe Hypoxemia (<90%)"
            hr = random.gauss(120, 12)
            rmssd = random.gauss(16, 4)
            jerk = max(0.05, random.gauss(0.8, 0.4))
            spo2 = random.gauss(85.5, 2.2) + noise_spo2
            skin_temp = random.gauss(33.6, 0.7) + noise_temp
            amb_temp = random.gauss(24.0, 2.0)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(15.0, random.gauss(50.0, 12.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.15)
        elif sub < 0.75:
            tag = "2D: Severe Bradycardia"
            hr = random.gauss(39, 4)
            rmssd = random.gauss(6, 2)
            jerk = max(0.05, random.gauss(0.2, 0.1))
            spo2 = random.gauss(89.0, 2.0) + noise_spo2
            skin_temp = random.gauss(32.2, 0.8) + noise_temp
            amb_temp = random.gauss(22.0, 2.0)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(15.0, random.gauss(45.0, 10.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.0, 0.10)
        elif sub < 0.88:
            tag = "2E: Heat Stroke Collapse"
            hr = random.gauss(158, 12)
            rmssd = random.gauss(8, 2)
            jerk = max(0.1, random.gauss(1.0, 0.6))
            spo2 = random.gauss(91.0, 1.8) + noise_spo2
            skin_temp = random.gauss(40.4, 0.6) + noise_temp
            amb_temp = random.gauss(45.0, 2.5)
            amb_hum = random.gauss(75.0, 5.0) + noise_hum
            aqi = max(30.0, random.gauss(90.0, 20.0) + noise_aqi)
            pressure = base_pressure + random.gauss(0, 1.0)
            flood_risk = random.uniform(0.10, 0.30)
        elif sub < 0.96:
            tag = "2F: Traumatic Fall Impact"
            hr = random.gauss(135, 14)
            rmssd = random.gauss(12, 3)
            jerk = max(25.0, random.gauss(34.0, 6.0))
            spo2 = random.gauss(94.0, 1.5) + noise_spo2
            skin_temp = random.gauss(34.5, 0.6) + noise_temp
            amb_temp = random.gauss(25.0, 2.0)
            amb_hum = random.gauss(50.0, 5.0) + noise_hum
            aqi = max(15.0, random.gauss(50.0, 12.0) + noise_aqi)
            pressure = base_pressure + 0.15
            flood_risk = random.uniform(0.0, 0.15)
        else:
            tag = "2G: Severe Storm / Barometric Plunge"
            hr = random.gauss(125, 12)
            rmssd = random.gauss(14, 3)
            jerk = max(2.0, random.gauss(6.0, 2.0))
            spo2 = random.gauss(95.0, 1.0) + noise_spo2
            skin_temp = random.gauss(32.0, 0.8) + noise_temp
            amb_temp = random.gauss(18.0, 3.0)
            amb_hum = random.gauss(92.0, 4.0) + noise_hum
            aqi = max(20.0, random.gauss(50.0, 15.0) + noise_aqi)
            pressure = 945.0 + random.gauss(0, 8.0)
            flood_risk = random.uniform(0.70, 0.95)
        label = 2
        tier = "CRITICAL_RED"

    # Apply physical clip bounds
    hr = round(max(30.0, min(230.0, hr)), 1)
    rmssd = round(max(2.0, min(180.0, rmssd)), 1)
    spo2 = round(max(65.0, min(100.0, spo2)), 1)
    skin_temp = round(max(28.0, min(43.5, skin_temp)), 2)
    amb_temp = round(max(-10.0, min(58.0, amb_temp)), 2)
    amb_hum = round(max(5.0, min(100.0, amb_hum)), 1)
    jerk = round(max(0.05, min(65.0, jerk)), 2)
    aqi = round(max(0.0, min(500.0, aqi)), 1)
    pressure = round(max(650.0, min(1100.0, pressure)), 2)
    flood_risk = round(max(0.0, min(1.0, flood_risk)), 3)

    feat_vector = [hr, rmssd, spo2, skin_temp, amb_temp, amb_hum, jerk, aqi, pressure, flood_risk]
    csv_row = [sample_id, tag, hr, rmssd, spo2, skin_temp, amb_temp, amb_hum, jerk, aqi, pressure, flood_risk, label, tier]
    return feat_vector, label, tag, csv_row

def generate_5_million_dataset(num_samples=5000000, random_seed=42, chunk_size=100000):
    """
    Generates 5,000,000 multi-modal samples and streams directly to CSV in chunks
    to ensure minimal memory footprint and high write throughput.
    """
    random.seed(random_seed)
    os.makedirs("ml_pipeline/data", exist_ok=True)
    csv_path = "ml_pipeline/data/wearable_5M_dataset.csv"

    print(f"==========================================================================")
    print(f"GENERATING 5 MILLION ({num_samples:,}) MULTI-MODAL SAMPLES")
    print(f"Target CSV: {csv_path}")
    print(f"==========================================================================")

    start_time = time.time()
    
    header = [
        "sample_id", "scenario_tag", "heart_rate_bpm", "rmssd_ms", "spo2_pct",
        "skin_temp_c", "ambient_temp_c", "ambient_humidity_pct", "imu_jerk_ms3",
        "aqi_ppm", "barometric_pressure_hpa", "flood_threat_index", "risk_class", "risk_tier"
    ]

    class_counts = {0: 0, 1: 0, 2: 0}
    sample_id = 0

    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)

        buffer = []
        num_chunks = math.ceil(num_samples / chunk_size)

        for chunk_idx in range(num_chunks):
            current_chunk_size = min(chunk_size, num_samples - sample_id)
            buffer.clear()

            for _ in range(current_chunk_size):
                sample_id += 1
                _, label, _, row = generate_sample(sample_id)
                buffer.append(row)
                class_counts[label] += 1

            writer.writerows(buffer)
            written = sample_id
            pct = (written / num_samples) * 100
            elapsed = time.time() - start_time
            rate = written / elapsed if elapsed > 0 else 0
            print(f"  [Chunk {chunk_idx+1}/{num_chunks}] Written {written:,} / {num_samples:,} rows ({pct:.1f}%) - {rate:,.0f} rows/s")

    total_time = time.time() - start_time
    file_size_mb = os.path.getsize(csv_path) / (1024 * 1024)

    print(f"\n==========================================================================")
    print(f"5 MILLION DATASET GENERATION COMPLETE")
    print(f"==========================================================================")
    print(f"  • File: {csv_path} ({file_size_mb:.2f} MB)")
    print(f"  • Total Rows: {num_samples:,}")
    print(f"  • Time Taken: {total_time:.2f}s ({num_samples/total_time:,.0f} rows/s)")
    print(f"  • Class 0 (Normal / Routine):               {class_counts[0]:,} ({class_counts[0]/num_samples*100:.1f}%)")
    print(f"  • Class 1 (Environmental & Heat Strain):    {class_counts[1]:,} ({class_counts[1]/num_samples*100:.1f}%)")
    print(f"  • Class 2 (Life Emergencies & Flood/Crash): {class_counts[2]:,} ({class_counts[2]/num_samples*100:.1f}%)")

    return csv_path

def generate_1_lakh_dataset(num_samples=100000, random_seed=42):
    """Generates 100,000 samples in memory for training pipeline ingestion."""
    random.seed(random_seed)
    features = []
    labels = []
    scenario_tags = []
    rows_for_csv = []

    for i in range(1, num_samples + 1):
        feat, label, tag, row = generate_sample(i)
        features.append(feat)
        labels.append(label)
        scenario_tags.append(tag)
        rows_for_csv.append(row)

    # Save to 100k CSV
    csv_path = "ml_pipeline/data/wearable_100k_dataset.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "sample_id", "scenario_tag", "heart_rate_bpm", "rmssd_ms", "spo2_pct",
            "skin_temp_c", "ambient_temp_c", "ambient_humidity_pct", "imu_jerk_ms3",
            "aqi_ppm", "barometric_pressure_hpa", "flood_threat_index", "risk_class", "risk_tier"
        ])
        writer.writerows(rows_for_csv)

    # Save compact json
    json_path = "ml_pipeline/data/synthetic_dataset.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"features": features, "labels": labels, "scenarios": scenario_tags}, f)

    return features, labels, scenario_tags

if __name__ == "__main__":
    import sys
    num = 5000000 if len(sys.argv) < 2 else int(sys.argv[1])
    if num > 100000:
        generate_5_million_dataset(num)
    else:
        generate_1_lakh_dataset(num)
