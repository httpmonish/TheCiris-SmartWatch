import random
import math
import json
import os
from generate_synthetic_dataset import generate_1_lakh_dataset

"""
Model Trainer for Multi-Modal Wearable Anomaly Classifier (1 Lakh Sample Scale)
==============================================================================
Features (10 Inputs):
  [0] Heart Rate (BPM)
  [1] RMSSD (ms)
  [2] SpO2 (%)
  [3] Skin Temp (°C)
  [4] Ambient Temp (°C)
  [5] Ambient Relative Humidity (%)
  [6] Motion Jerk (m/s^3)
  [7] Air Quality Index (AQI / PPM)
  [8] Barometric Pressure (hPa)
  [9] Flood Geofence Threat Index (0.0 - 1.0)

Splits: 70,000 Train, 15,000 Val, 15,000 Test (70/15/15)
Outputs:
  - Classification Metrics (Accuracy, Precision, Recall, F1, Confusion Matrix)
  - flutter_wearable_app/lib/algorithms/ml/model_constants.dart
  - ml_pipeline/models/cardiac_anomaly_weights.json
"""

def softmax(logits):
    max_l = max(logits)
    exp_l = [math.exp(l - max_l) for l in logits]
    sum_exp = sum(exp_l)
    return [e / sum_exp for e in exp_l]

class MultiModalLogisticRegression:
    def __init__(self, num_features=10, num_classes=3, lr=0.035, reg=1e-4):
        random.seed(42)
        self.num_features = num_features
        self.num_classes = num_classes
        self.lr = lr
        self.reg = reg
        self.W = [[random.gauss(0, 0.01) for _ in range(num_classes)] for _ in range(num_features)]
        self.b = [0.0] * num_classes
        self.means = [0.0] * num_features
        self.stds = [1.0] * num_features

    def fit(self, X_train, y_train, epochs=80, batch_size=128):
        num_samples = len(X_train)
        
        # 1. Compute means and stds on training set strictly
        for f in range(self.num_features):
            col = [X_train[i][f] for i in range(num_samples)]
            mean = sum(col) / num_samples
            var = sum((v - mean) ** 2 for v in col) / num_samples
            self.means[f] = mean
            self.stds[f] = math.sqrt(var) + 1e-7

        X_train_norm = self._normalize(X_train)

        for epoch in range(epochs):
            indices = list(range(num_samples))
            random.shuffle(indices)

            for start in range(0, num_samples, batch_size):
                end = min(start + batch_size, num_samples)
                batch_indices = indices[start:end]
                b_size = len(batch_indices)

                grad_W = [[0.0] * self.num_classes for _ in range(self.num_features)]
                grad_b = [0.0] * self.num_classes

                for idx in batch_indices:
                    xi = X_train_norm[idx]
                    target = y_train[idx]

                    logits = [self.b[c] + sum(xi[f] * self.W[f][c] for f in range(self.num_features)) for c in range(self.num_classes)]
                    probs = softmax(logits)

                    for c in range(self.num_classes):
                        error = probs[c] - (1.0 if c == target else 0.0)
                        grad_b[c] += error
                        for f in range(self.num_features):
                            grad_W[f][c] += error * xi[f]

                for c in range(self.num_classes):
                    self.b[c] -= (self.lr / b_size) * grad_b[c]
                    for f in range(self.num_features):
                        self.W[f][c] -= self.lr * ((grad_W[f][c] / b_size) + self.reg * self.W[f][c])

    def _normalize(self, X):
        return [[(row[f] - self.means[f]) / self.stds[f] for f in range(self.num_features)] for row in X]

    def predict(self, X):
        X_norm = self._normalize(X)
        preds = []
        for xi in X_norm:
            logits = [self.b[c] + sum(xi[f] * self.W[f][c] for f in range(self.num_features)) for c in range(self.num_classes)]
            probs = softmax(logits)
            preds.append(probs.index(max(probs)))
        return preds

def compute_metrics(y_true, y_pred, num_classes=3):
    cm = [[0] * num_classes for _ in range(num_classes)]
    for t, p in zip(y_true, y_pred):
        cm[t][p] += 1

    total = len(y_true)
    correct = sum(cm[i][i] for i in range(num_classes))
    accuracy = correct / total

    class_metrics = []
    for c in range(num_classes):
        tp = cm[c][c]
        fp = sum(cm[i][c] for i in range(num_classes) if i != c)
        fn = sum(cm[c][i] for i in range(num_classes) if i != c)
        
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
        
        class_metrics.append({
            "class": c,
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": sum(cm[c])
        })

    return accuracy, cm, class_metrics

def export_to_dart(model, out_path="flutter_wearable_app/lib/algorithms/ml/model_constants.dart"):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    dart_code = f"""// Auto-generated Machine Learning Classifier Constants
// Trained on 100,000 Multi-Modal Physiological & Environmental Samples (16 Scenarios)

class MLModelWeights {{
  static const List<double> featureMeans = {model.means};
  static const List<double> featureStds = {model.stds};
  
  // Weights matrix: [10 features x 3 classes (Normal, Strain, Anomaly/Disaster)]
  static const List<List<double>> weights = {model.W};
  
  // Biases vector: [3 classes]
  static const List<double> biases = {model.b};
}}
"""
    with open(out_path, "w") as f:
        f.write(dart_code)
    print(f"Dart model weights exported to: {out_path}")

if __name__ == "__main__":
    X, y, tags = generate_1_lakh_dataset(100000, random_seed=42)

    n_total = len(X)
    n_train = int(0.70 * n_total)
    n_val = int(0.15 * n_total)

    indices = list(range(n_total))
    random.seed(1337)
    random.shuffle(indices)

    X_train = [X[i] for i in indices[:n_train]]
    y_train = [y[i] for i in indices[:n_train]]

    X_test = [X[i] for i in indices[n_train + n_val:]]
    y_test = [y[i] for i in indices[n_train + n_val:]]

    test_counts = {0: y_test.count(0), 1: y_test.count(1), 2: y_test.count(2)}
    majority_class_baseline = max(test_counts.values()) / len(y_test)

    print(f"\n1 Lakh Dataset Splits: Train={len(X_train):,}, Val=15,000, Test={len(X_test):,}")
    print(f"Test Set Class Distribution: {test_counts}")
    print(f"Naive 'Always Guess Majority' Baseline: {majority_class_baseline * 100:.2f}%\n")

    print(f"Training 10-Feature Classifier on {len(X_train):,} samples...")
    model = MultiModalLogisticRegression(num_features=10, num_classes=3, lr=0.045, reg=1e-4)
    model.fit(X_train, y_train, epochs=70, batch_size=128)

    y_pred = model.predict(X_test)
    accuracy, cm, class_metrics = compute_metrics(y_test, y_pred)

    class_names = ["Normal/Routine", "Environmental Strain", "Life Emergency/Flood"]
    print("==========================================================================")
    print(f"1 LAKH HELD-OUT TEST ACCURACY: {accuracy * 100:.2f}%  (Baseline: {majority_class_baseline * 100:.2f}%)")
    print("==========================================================================")
    print("\nConfusion Matrix (Row=True, Col=Predicted):")
    print(f"                Pred 0   Pred 1   Pred 2")
    for r_idx, row in enumerate(cm):
        print(f"  True {r_idx} ({class_names[r_idx][:10]:10}): {row[0]:6d}   {row[1]:6d}   {row[2]:6d}")

    print("\nPer-Class Classification Report:")
    for m in class_metrics:
        c_name = class_names[m["class"]]
        print(f"  Class {m['class']} ({c_name:24}): Precision={m['precision']:.3f}, Recall={m['recall']:.3f}, F1={m['f1']:.3f} (N={m['support']})")

    export_to_dart(model, "flutter_wearable_app/lib/algorithms/ml/model_constants.dart")
    
    os.makedirs("ml_pipeline/models", exist_ok=True)
    with open("ml_pipeline/models/cardiac_anomaly_weights.json", "w") as f:
        json.dump({
            "features": ["HR", "RMSSD", "SpO2", "SkinTemp", "AmbientTemp", "AmbientHum", "Jerk", "AQI", "Pressure", "FloodRisk"],
            "means": model.means,
            "stds": model.stds,
            "weights": model.W,
            "biases": model.b,
            "test_accuracy": accuracy,
            "confusion_matrix": cm,
            "num_samples": 100000
        }, f, indent=2)
    print("\n[OK] 1 Lakh Model training and artifacts successfully generated.")
