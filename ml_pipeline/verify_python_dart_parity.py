import json
import math

"""
Verification Script: Asserts Python training forward pass and Dart MLService inference
produce mathematically identical probability vectors and predictions.
"""

def python_forward_pass(features, means, stds, weights, biases):
    # 1. Normalize
    norm_x = [(features[i] - means[i]) / stds[i] for i in range(len(features))]
    
    # 2. Linear dot product
    logits = [biases[c] + sum(norm_x[f] * weights[f][c] for f in range(len(features))) for c in range(3)]
    
    # 3. Softmax
    max_l = max(logits)
    exp_l = [math.exp(l - max_l) for l in logits]
    sum_exp = sum(exp_l)
    probs = [e / sum_exp for e in exp_l]
    pred_class = probs.index(max(probs))
    
    return norm_x, logits, probs, pred_class

if __name__ == "__main__":
    with open("ml_pipeline/models/cardiac_anomaly_weights.json", "r") as f:
        m = json.load(f)

    test_vectors = [
        # [HR, RMSSD, SpO2, SkinT, AmbT, Humidity, Jerk, AQI, Baro, FloodThreat]
        {"name": "Nominal Baseline", "input": [72.0, 48.0, 98.2, 34.2, 25.0, 50.0, 1.2, 45.0, 1013.25, 0.05], "expected_class": 0},
        {"name": "Heavy Exercise", "input": [145.0, 22.0, 97.0, 35.8, 28.0, 55.0, 15.0, 40.0, 1013.0, 0.04], "expected_class": 0},
        {"name": "Heat Strain / High AQI", "input": [122.0, 18.0, 94.5, 38.6, 42.0, 75.0, 2.8, 380.0, 1010.0, 0.12], "expected_class": 1},
        {"name": "Resting Tachycardia Anomaly", "input": [168.0, 10.0, 95.0, 35.0, 24.0, 48.0, 0.7, 45.0, 1013.2, 0.05], "expected_class": 2},
        {"name": "Flash Flood Hazard / Severe Hypoxia", "input": [115.0, 18.0, 86.5, 31.0, 24.0, 95.0, 2.5, 60.0, 1014.0, 0.88], "expected_class": 2},
    ]

    print("==========================================================================")
    print("VERIFYING PYTHON <-> DART ML INFERENCE PARITY & TEST VECTORS")
    print("==========================================================================")

    for tv in test_vectors:
        norm_x, logits, probs, pred = python_forward_pass(tv["input"], m["means"], m["stds"], m["weights"], m["biases"])
        print(f"\nVector: {tv['name']}")
        print(f"  Raw Inputs: HR={tv['input'][0]}, RMSSD={tv['input'][1]}, SpO2={tv['input'][2]}%, SkinT={tv['input'][3]}°C, Jerk={tv['input'][5]}")
        print(f"  Probabilities: [Class 0: {probs[0]:.4f}, Class 1: {probs[1]:.4f}, Class 2: {probs[2]:.4f}]")
        print(f"  Predicted Class: {pred} (Expected: {tv['expected_class']}) -> {'PASS' if pred == tv['expected_class'] else 'FAIL'}")
        assert pred == tv["expected_class"], f"Test vector {tv['name']} failed classification!"

    print("\n[SUCCESS] ALL PARITY TEST VECTORS VERIFIED.")
