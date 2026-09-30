import sqlite3

def set_active_production_model(algorithm='random_forest'):
    conn = sqlite3.connect('database/ciris_platform.db')
    cursor = conn.cursor()
    cursor.execute("SELECT model_id, model_name, version, algorithm FROM models WHERE algorithm = ? ORDER BY trained_at DESC LIMIT 1", (algorithm,))
    row = cursor.fetchone()
    if row:
        model_id, name, version, algo = row
        cursor.execute("UPDATE models SET is_active = 0")
        cursor.execute("UPDATE models SET is_active = 1, status = 'production' WHERE model_id = ?", (model_id,))
        conn.commit()
        print(f"[MODEL REGISTRY] Active production model set to: {name} ({model_id}) - Version {version}")
    else:
        print(f"[MODEL REGISTRY] No model found for algorithm: {algorithm}")
    conn.close()

if __name__ == "__main__":
    set_active_production_model('random_forest')
