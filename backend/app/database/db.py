"""SQLite database layer. ONE database for the whole app (Contract section 21).

Tables: sensor_readings, scans (history), users (minimal).
Every module uses this layer - no module creates its own database.
"""
import json
import sqlite3
import threading
from datetime import datetime, timezone
from typing import Optional

from ..config import settings


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, path: Optional[str] = None):
        self._path = path or settings.database_path
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self._path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self.init()

    def init(self) -> None:
        with self._lock, self._conn:
            self._conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sensor_readings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    temperature REAL NOT NULL,
                    humidity REAL NOT NULL,
                    soil_moisture REAL NOT NULL,
                    light REAL NOT NULL,
                    leaf_wetness REAL,
                    source TEXT NOT NULL,
                    timestamp TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS scans (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT,
                    crop_name TEXT NOT NULL,
                    device_id TEXT,
                    timestamp TEXT NOT NULL,
                    disease_name TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    model_status TEXT NOT NULL,
                    risk_level TEXT NOT NULL,
                    risk_score INTEGER NOT NULL,
                    risk_factors TEXT,
                    future_risk TEXT,
                    explanation TEXT,
                    recommendations TEXT,
                    image_path TEXT
                );
                """
            )
            # Additive migrations keep existing SQLite databases usable.
            columns = {
                row[1] for row in self._conn.execute("PRAGMA table_info(scans)")
            }
            for name, definition in (
                ("plant_name", "TEXT"),
                ("plant_confidence", "REAL"),
                ("plant_status", "TEXT"),
                ("disease_status", "TEXT"),
                ("disease_candidates", "TEXT"),
                ("image_quality", "TEXT"),
                ("model_version", "TEXT"),
            ):
                if name not in columns:
                    self._conn.execute(
                        f"ALTER TABLE scans ADD COLUMN {name} {definition}"
                    )

    # ---------- sensors ----------

    def insert_sensor(self, data: dict) -> None:
        source = "SIMULATED" if str(data["device_id"]).upper().startswith("SIMULATED") else "REAL"
        with self._lock, self._conn:
            self._conn.execute(
                """INSERT INTO sensor_readings
                   (device_id, temperature, humidity, soil_moisture, light,
                    leaf_wetness, source, timestamp)
                   VALUES (?,?,?,?,?,?,?,?)""",
                (
                    data["device_id"], data["temperature"], data["humidity"],
                    data["soil_moisture"], data["light"], data.get("leaf_wetness"),
                    data.get("source") or source,
                    data.get("timestamp") or _now(),
                ),
            )

    def latest_sensor(self, device_id: Optional[str] = None) -> Optional[dict]:
        sql = "SELECT * FROM sensor_readings"
        args: tuple = ()
        if device_id:
            sql += " WHERE device_id = ?"
            args = (device_id,)
        sql += " ORDER BY timestamp DESC LIMIT 1"
        with self._lock:
            row = self._conn.execute(sql, args).fetchone()
        return dict(row) if row else None

    def sensor_history(self, device_id: Optional[str] = None, limit: int = 200) -> list:
        sql = "SELECT * FROM sensor_readings"
        args: list = []
        if device_id:
            sql += " WHERE device_id = ?"
            args.append(device_id)
        sql += " ORDER BY timestamp DESC LIMIT ?"
        args.append(limit)
        with self._lock:
            rows = self._conn.execute(sql, args).fetchall()
        return [dict(r) for r in rows]

    # ---------- scans / history ----------

    def insert_scan(self, record: dict) -> int:
        with self._lock, self._conn:
            cur = self._conn.execute(
                """INSERT INTO scans
                   (user_id, crop_name, device_id, timestamp, disease_name, confidence,
                    model_status, risk_level, risk_score, risk_factors, future_risk,
                    explanation, recommendations, image_path, plant_name,
                    plant_confidence, plant_status, disease_status,
                    disease_candidates, image_quality, model_version)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    record.get("user_id"), record["crop_name"], record.get("device_id"),
                    record.get("timestamp") or _now(), record["disease_name"],
                    record["confidence"], record["model_status"], record["risk_level"],
                    record["risk_score"], json.dumps(record.get("risk_factors", [])),
                    json.dumps(record.get("future_risk", {})),
                    json.dumps(record.get("explanation", {})),
                    json.dumps(record.get("recommendations", {})),
                    record.get("image_path"),
                    record.get("plant_name"),
                    record.get("plant_confidence"),
                    record.get("plant_status"),
                    record.get("disease_status"),
                    json.dumps(record.get("disease_candidates", [])),
                    json.dumps(record.get("image_quality", {})),
                    record.get("model_version"),
                ),
            )
            return int(cur.lastrowid)

    def history(self, limit: int = 50) -> list:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM scans ORDER BY timestamp DESC LIMIT ?", (limit,)
            ).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            for k in ("risk_factors", "future_risk", "explanation", "recommendations",
                      "disease_candidates", "image_quality"):
                try:
                    d[k] = json.loads(d[k]) if d[k] else None
                except (TypeError, json.JSONDecodeError):
                    pass
            out.append(d)
        return out

    def get_scan(self, scan_id: int) -> Optional[dict]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM scans WHERE id = ?", (scan_id,)
            ).fetchone()
        if not row:
            return None
        d = dict(row)
        for k in ("risk_factors", "future_risk", "explanation", "recommendations",
                  "disease_candidates", "image_quality"):
            try:
                d[k] = json.loads(d[k]) if d[k] else None
            except (TypeError, json.JSONDecodeError):
                pass
        return d


db = Database()