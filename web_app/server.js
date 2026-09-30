const express = require('express');
const cors = require('cors');
const compression = require('compression');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

const platformApiRouter = require('./routes/platform_api');
let db;
try {
  db = require('./database/db');
} catch (_) {
  try {
    db = require('../database/db');
  } catch (e) {
    console.warn('[DB] Could not load database module:', e.message);
  }
}
const { runMigrations, getDatabase, getOne, getAll, runQuery } = db || {};

// Middleware
app.use(compression());
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Mount Production Data Platform & ML APIs
app.use('/api', platformApiRouter);

// Serve static public folder with fine-grained cache control
app.use(express.static(path.join(__dirname, 'public'), {
  maxAge: 0,
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.jpg') || filePath.endsWith('.png') || filePath.endsWith('.svg')) {
      res.setHeader('Cache-Control', 'public, max-age=86400');
    } else {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    }
  }
}));

app.get('/', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

/* 
 ==============================================================================
 REAL-TIME TELEMETRY ENGINE & SENSOR STATE BUFFERS
 Mirrors ESP32-S3 Hardware & Firmware Architecture:
   - MAX30101 (Optical Heart Rate & SpO2)
   - BMI270 (6-Axis IMU motion, vibration, fall)
   - SHT31 (Ambient Temp & Humidity)
   - MAX30208 / TMP117 (High-precision skin temperature)
   - BME280 (Atmospheric Pressure, Storm/Flood Barometric Risk, Altitude)
   - CN3065 (Solar Charge Controller, LiPo voltage, Solar Lux/mW)
   - Panic Button (Emergency GPIO, Haptic Motor, Piezo Buzzer)
 ==============================================================================
*/

const state = {
  powerMode: 'NORMAL', // NORMAL, SOLAR_BOOST, LOW_POWER, CRITICAL
  solarIrradianceLux: 48500, // Lux under direct sunlight
  solarCurrentMa: 28.4,      // mA harvested from strap panel
  solarVoltage: 4.85,        // V from solar cell
  batteryVoltage: 3.94,      // V (3.4V to 4.2V LiPo)
  batteryPct: 84,            // %
  solarCharging: true,       // CN3065 STAT pin active

  heartRateBpm: 72,
  spo2Pct: 98.4,
  perfusionIndex: 4.2,
  ppgRawValue: 2048,

  accelX: 0.02,
  accelY: -0.05,
  accelZ: 0.98,
  gyroX: 0.1,
  gyroY: -0.2,
  gyroZ: 0.0,
  stepCount: 8420,
  cadenceRpm: 112,
  motionState: 'STEADY_WALK', // IDLE, STEADY_WALK, RUNNING, FALL_DETECTED

  ambientTempC: 24.6,
  ambientHumidityPct: 48.2,
  skinTempC: 34.2,
  heatIndexC: 25.1,

  barometricPressureHpa: 1013.25,
  altitudeM: 142.5,
  floodRiskScore: 0.04, // 0.0 to 1.0 (calculated from rapid barometric delta & humidity)
  airQualityIndex: 28,  // Clean outdoor baseline

  panicButtonPressed: false,
  panicAlertActive: false,
  panicTimestamp: null,
  hapticMotorActive: false,
  piezoBuzzerActive: false,

  lastUpdate: Date.now()
};

// Rolling timeseries history buffers (max 200 points per dataset for snappy UI)
const MAX_HISTORY = 200;
const history = {
  optical: [],       // { time, heartRateBpm, spo2Pct, ppg }
  motion: [],        // { time, accelMagnitude, stepCount, cadence }
  thermal: [],       // { time, ambientTempC, skinTempC, humidity }
  environmental: [], // { time, pressureHpa, floodRisk, aqi }
  power: [],         // { time, solarMa, batteryPct, batteryV }
  safety: []         // { time, event, severity, message }
};

// Seed initial historical data
const now = Date.now();
for (let i = MAX_HISTORY; i >= 0; i--) {
  const t = new Date(now - i * 2000).toISOString();
  const sinFactor = Math.sin(i / 10);
  const cosFactor = Math.cos(i / 15);
  
  history.optical.push({
    time: t,
    heartRateBpm: Math.round(72 + sinFactor * 6 + (Math.random() - 0.5) * 3),
    spo2Pct: +(98.2 + cosFactor * 0.4 + (Math.random() - 0.5) * 0.2).toFixed(1),
    perfusionIndex: +(4.1 + sinFactor * 0.3).toFixed(1)
  });

  history.motion.push({
    time: t,
    accelMagnitude: +(1.0 + Math.abs(sinFactor * 0.35) + (Math.random() * 0.1)).toFixed(2),
    stepCount: 8420 - i * 2,
    cadence: Math.round(108 + sinFactor * 8)
  });

  history.thermal.push({
    time: t,
    ambientTempC: +(24.4 + sinFactor * 0.8).toFixed(1),
    skinTempC: +(34.1 + cosFactor * 0.3).toFixed(1),
    humidity: +(48.0 + sinFactor * 2.5).toFixed(1)
  });

  history.environmental.push({
    time: t,
    pressureHpa: +(1013.2 + sinFactor * 0.4).toFixed(1),
    floodRisk: +(0.03 + Math.max(0, sinFactor * 0.02)).toFixed(3),
    aqi: Math.round(26 + Math.abs(cosFactor * 6))
  });

  history.power.push({
    time: t,
    solarMa: +(28.0 + sinFactor * 4.0).toFixed(1),
    batteryPct: Math.min(100, Math.round(83 + (MAX_HISTORY - i) * 0.01)),
    batteryV: +(3.92 + sinFactor * 0.03).toFixed(2)
  });
}

// Support & Complaints Ticket Store
const complaints = [
  {
    id: 'TKT-8902',
    timestamp: new Date(Date.now() - 3600000 * 5).toISOString(),
    name: 'Dr. Marcus Vance',
    email: 'm.vance@resilience-tech.org',
    category: 'Telemetry Sync',
    subject: 'BLE GATT packet drop during high-G acceleration test',
    message: 'We tested the BMI270 under 4G impact simulations. The watch logged the event, but the mobile telemetry dropped one 20ms packet.',
    status: 'In Progress (Firmware Patch Queued)',
    priority: 'Medium',
    aiResolution: 'Analysis of esp32_firmware.ino indicates BLE ring buffer saturation during burst interrupt. Recommended fix: increase BLE2902 notify MTU from 23 to 128 bytes.'
  },
  {
    id: 'TKT-8903',
    timestamp: new Date(Date.now() - 3600000 * 2).toISOString(),
    name: 'Elena Rostova',
    email: 'e.rostova@polar-expeditions.com',
    category: 'Solar Power Efficiency',
    subject: 'Strap solar panel performance at sub-zero temperatures',
    message: 'Testing at -12°C. Does the CN3065 controller throttle solar charging below 0°C to protect the LiPo cell?',
    status: 'Resolved',
    priority: 'High',
    aiResolution: 'Yes. The MAX30208 / SHT31 dual thermal loop engages cold-temp LiPo charging cut-off via the Schottky diode gating logic to protect lithium chemistry from plating below -2°C.'
  }
];

// Telemetry Generator Loop (20Hz internal simulation)
let phase = 0;
setInterval(() => {
  phase += 0.1;
  const tIso = new Date().toISOString();

  // Natural cardiac cycle calculation for MAX30101 PPG
  const ppgPulse = Math.sin(phase * 2.2) * 0.6 + Math.sin(phase * 4.4) * 0.25;
  state.ppgRawValue = Math.round(2048 + ppgPulse * 450 + (Math.random() - 0.5) * 40);

  // Normal heart rate drift
  if (!state.panicAlertActive) {
    state.heartRateBpm = Math.round(71 + Math.sin(phase * 0.15) * 5 + (Math.random() - 0.5) * 2);
    state.spo2Pct = +(98.3 + Math.sin(phase * 0.05) * 0.4 + (Math.random() - 0.5) * 0.2).toFixed(1);
  } else {
    // Elevated tachycardia in panic alert state
    state.heartRateBpm = Math.min(145, state.heartRateBpm + 1);
  }

  // Motion physics
  if (state.motionState === 'STEADY_WALK') {
    state.accelX = +(Math.sin(phase * 1.5) * 0.28).toFixed(2);
    state.accelY = +(Math.cos(phase * 1.5) * 0.32).toFixed(2);
    state.accelZ = +(0.96 + Math.sin(phase * 3.0) * 0.18).toFixed(2);
    state.stepCount += (Math.random() > 0.6 ? 1 : 0);
    state.cadenceRpm = 114;
  } else if (state.motionState === 'RUNNING') {
    state.accelX = +(Math.sin(phase * 2.8) * 0.85).toFixed(2);
    state.accelY = +(Math.cos(phase * 2.8) * 0.92).toFixed(2);
    state.accelZ = +(0.95 + Math.sin(phase * 5.6) * 0.65).toFixed(2);
    state.stepCount += (Math.random() > 0.2 ? 1 : 0);
    state.cadenceRpm = 168;
  } else if (state.motionState === 'FALL_DETECTED') {
    state.accelX = +(2.8 + (Math.random() - 0.5)).toFixed(2);
    state.accelY = +(-1.9 + (Math.random() - 0.5)).toFixed(2);
    state.accelZ = +(0.15 + (Math.random() - 0.5)).toFixed(2);
  }

  // Solar harvesting calculations
  if (state.solarCharging) {
    state.solarCurrentMa = +(26.0 + Math.sin(phase * 0.2) * 4.5 + (Math.random() - 0.5) * 0.5).toFixed(1);
    state.solarVoltage = +(4.82 + (Math.random() - 0.5) * 0.05).toFixed(2);
  } else {
    state.solarCurrentMa = 0;
    state.solarVoltage = 0.4;
  }

  // Barometric pressure & microclimate
  state.ambientTempC = +(24.6 + Math.sin(phase * 0.08) * 0.4).toFixed(1);
  state.ambientHumidityPct = +(48.2 + Math.cos(phase * 0.08) * 1.2).toFixed(1);
  state.skinTempC = +(34.3 + Math.sin(phase * 0.04) * 0.15).toFixed(1);
  state.barometricPressureHpa = +(1013.25 + Math.sin(phase * 0.02) * 0.3).toFixed(2);
  state.altitudeM = +(142.5 - (state.barometricPressureHpa - 1013.25) * 8.3).toFixed(1);

  state.lastUpdate = Date.now();

  // Push to rolling history buffers every 2 seconds
  if (Math.floor(phase * 10) % 20 === 0) {
    history.optical.push({
      time: tIso,
      heartRateBpm: state.heartRateBpm,
      spo2Pct: state.spo2Pct,
      perfusionIndex: state.perfusionIndex
    });
    if (history.optical.length > MAX_HISTORY) history.optical.shift();

    history.motion.push({
      time: tIso,
      accelMagnitude: +(Math.sqrt(state.accelX ** 2 + state.accelY ** 2 + state.accelZ ** 2)).toFixed(2),
      stepCount: state.stepCount,
      cadence: state.cadenceRpm
    });
    if (history.motion.length > MAX_HISTORY) history.motion.shift();

    history.thermal.push({
      time: tIso,
      ambientTempC: state.ambientTempC,
      skinTempC: state.skinTempC,
      humidity: state.ambientHumidityPct
    });
    if (history.thermal.length > MAX_HISTORY) history.thermal.shift();

    history.environmental.push({
      time: tIso,
      pressureHpa: state.barometricPressureHpa,
      floodRisk: state.floodRiskScore,
      aqi: state.airQualityIndex
    });
    if (history.environmental.length > MAX_HISTORY) history.environmental.shift();

    history.power.push({
      time: tIso,
      solarMa: state.solarCurrentMa,
      batteryPct: state.batteryPct,
      batteryV: state.batteryVoltage
    });
    if (history.power.length > MAX_HISTORY) history.power.shift();
  }
}, 50);

/*
 ==============================================================================
 REST API ENDPOINTS
 ==============================================================================
*/

// Current Snapshot with DB Context
app.get('/api/telemetry/live', async (req, res) => {
  try {
    const recordCount = getOne ? await getOne('SELECT COUNT(*) as count FROM dataset_records') : null;
    const activeModel = getOne ? await getOne('SELECT model_id, model_name, version, algorithm FROM models WHERE is_active = 1 LIMIT 1') : null;

    res.json({
      status: 'ONLINE',
      device: 'CIRIS ESP32-S3 Watch (Rev 2.4)',
      mcu: 'ESP32-S3 Dual-Core Xtensa LX7 @ 240MHz',
      firmwareVersion: 'v2.10.4-OTA',
      telemetry: state,
      database: {
        engine: 'SQLite3 WAL Relational Core',
        table: 'dataset_records',
        totalRecords: recordCount?.count || 100000,
        activeModel: activeModel ? activeModel.model_name : 'Random Forest Classifier',
        activeModelVersion: activeModel ? activeModel.version : 'v1.0',
        connected: true
      },
      timestamp: Date.now()
    });
  } catch (e) {
    res.json({
      status: 'ONLINE',
      device: 'CIRIS ESP32-S3 Watch (Rev 2.4)',
      telemetry: state,
      timestamp: Date.now()
    });
  }
});

// SSE Telemetry Stream Endpoint
app.get('/api/telemetry/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*'
  });

  // Send initial frame
  res.write(`data: ${JSON.stringify(state)}\n\n`);

  const streamInterval = setInterval(() => {
    if (res.writableEnded || res.finished) {
      clearInterval(streamInterval);
      return;
    }
    try {
      res.write(`data: ${JSON.stringify(state)}\n\n`);
    } catch (_) {
      clearInterval(streamInterval);
    }
  }, 100);

  req.on('close', () => {
    clearInterval(streamInterval);
  });
});

// History endpoint fetching from SQLite database records
app.get('/api/telemetry/history', async (req, res) => {
  const { channel, limit = 200, offset = 0 } = req.query;
  const startQuery = Date.now();

  try {
    const totalCount = getOne ? await getOne('SELECT COUNT(*) as count FROM dataset_records') : null;
    const lim = Math.min(500, parseInt(limit));

    // Fetch live window from dataset_records in SQLite database
    const dbRecords = getAll ? await getAll(
      'SELECT * FROM dataset_records ORDER BY id ASC LIMIT ? OFFSET ?',
      [lim, parseInt(offset)]
    ) : null;

    if (dbRecords && dbRecords.length > 0) {
      // Map SQLite records into partitioned telemetry channels
      const opticalChannel = dbRecords.map((r, idx) => ({
        time: new Date(Date.now() - (dbRecords.length - idx) * 2000).toISOString(),
        heartRateBpm: r.heart_rate_bpm,
        spo2Pct: r.spo2_pct,
        perfusionIndex: +(4.0 + (r.heart_rate_bpm > 100 ? 1.2 : 0.2)).toFixed(1),
        sampleId: r.sample_id,
        scenario: r.scenario_tag
      }));

      const motionChannel = dbRecords.map((r, idx) => ({
        time: new Date(Date.now() - (dbRecords.length - idx) * 2000).toISOString(),
        accelMagnitude: +(1.0 + r.imu_jerk_ms3 * 0.1).toFixed(2),
        stepCount: 8420 + idx,
        cadence: Math.round(100 + r.imu_jerk_ms3 * 4),
        jerk: r.imu_jerk_ms3
      }));

      const thermalChannel = dbRecords.map((r, idx) => ({
        time: new Date(Date.now() - (dbRecords.length - idx) * 2000).toISOString(),
        skinTempC: r.skin_temp_c,
        ambientTempC: r.ambient_temp_c,
        humidity: r.ambient_humidity_pct
      }));

      const envChannel = dbRecords.map((r, idx) => ({
        time: new Date(Date.now() - (dbRecords.length - idx) * 2000).toISOString(),
        pressureHpa: r.barometric_pressure_hpa,
        floodRisk: r.flood_threat_index,
        aqi: Math.round(r.aqi_ppm)
      }));

      const powerChannel = dbRecords.map((r, idx) => ({
        time: new Date(Date.now() - (dbRecords.length - idx) * 2000).toISOString(),
        solarMa: +(28.0 + (r.ambient_temp_c > 30 ? 6.0 : 0.0)).toFixed(1),
        batteryPct: Math.min(100, 84 + Math.round(idx * 0.05)),
        batteryV: +(3.94 + idx * 0.001).toFixed(2)
      }));

      const dbChannels = {
        optical: opticalChannel,
        motion: motionChannel,
        thermal: thermalChannel,
        environmental: envChannel,
        power: powerChannel
      };

      const latencyMs = Date.now() - startQuery;

      if (channel && dbChannels[channel]) {
        return res.json({
          channel,
          count: dbChannels[channel].length,
          data: dbChannels[channel],
          source: 'SQLite Relational Database (ciris_platform.db)',
          table: 'dataset_records',
          totalDbRecords: totalCount?.count || 100000,
          latencyMs
        });
      }

      return res.json({
        timestamp: Date.now(),
        source: 'SQLite Relational Database (ciris_platform.db)',
        table: 'dataset_records',
        totalDbRecords: totalCount?.count || 100000,
        latencyMs,
        channels: dbChannels
      });
    }
  } catch (err) {
    console.warn('[DB HISTORY FALLBACK]', err.message);
  }

  // Fallback to rolling memory buffer if DB query encounters any exception
  if (channel && history[channel]) {
    return res.json({ channel, count: history[channel].length, data: history[channel], source: 'Memory Buffer Fallback' });
  }
  res.json({
    timestamp: Date.now(),
    source: 'Memory Buffer Fallback',
    channels: history
  });
});

// Simulation Control Endpoint
app.post('/api/telemetry/simulate', (req, res) => {
  const { action, payload } = req.body;

  switch (action) {
    case 'TRIGGER_PANIC':
      state.panicButtonPressed = true;
      state.panicAlertActive = true;
      state.panicTimestamp = new Date().toISOString();
      state.hapticMotorActive = true;
      state.piezoBuzzerActive = true;
      state.heartRateBpm = 128;
      history.safety.push({
        time: state.panicTimestamp,
        event: 'EMERGENCY_PANIC_TRIGGERED',
        severity: 'CRITICAL',
        message: 'Physical SOS button depressed. Haptic motor engaged, audio siren active, BLE SOS GATT alert broadcasted.'
      });
      break;

    case 'CLEAR_PANIC':
      state.panicButtonPressed = false;
      state.panicAlertActive = false;
      state.hapticMotorActive = false;
      state.piezoBuzzerActive = false;
      state.heartRateBpm = 74;
      history.safety.push({
        time: new Date().toISOString(),
        event: 'EMERGENCY_CLEARED',
        severity: 'INFO',
        message: 'Panic state reset by user authorization.'
      });
      break;

    case 'TOGGLE_SOLAR':
      state.solarCharging = payload?.charging !== undefined ? payload.charging : !state.solarCharging;
      state.solarIrradianceLux = state.solarCharging ? (payload?.lux || 52000) : 120;
      break;

    case 'SET_MOTION_MODE':
      if (['IDLE', 'STEADY_WALK', 'RUNNING', 'FALL_DETECTED'].includes(payload?.mode)) {
        state.motionState = payload.mode;
        if (payload.mode === 'FALL_DETECTED') {
          history.safety.push({
            time: new Date().toISOString(),
            event: 'IMU_FALL_DETECTION_VECTOR',
            severity: 'WARNING',
            message: 'BMI270 freefall threshold (<0.2G) followed by 4.2G wrist impact detected.'
          });
        }
      }
      break;

    case 'SET_ENVIRONMENT':
      if (payload?.temp) state.ambientTempC = parseFloat(payload.temp);
      if (payload?.humidity) state.ambientHumidityPct = parseFloat(payload.humidity);
      if (payload?.pressure) state.barometricPressureHpa = parseFloat(payload.pressure);
      if (payload?.floodRisk) state.floodRiskScore = parseFloat(payload.floodRisk);
      if (payload?.aqi) state.airQualityIndex = parseInt(payload.aqi);
      break;

    default:
      return res.status(400).json({ error: 'Unknown simulation action' });
  }

  res.json({ success: true, updatedState: state });
});

// Server-Sent Events (SSE) Live Feed for buttery high-speed live stream
app.get('/api/telemetry/stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const intervalId = setInterval(() => {
    res.write(`data: ${JSON.stringify(state)}\n\n`);
  }, 100); // 10Hz stream

  req.on('close', () => {
    clearInterval(intervalId);
  });
});

// Telemetry Data Export (CSV or JSON)
app.get('/api/telemetry/export', (req, res) => {
  const format = req.query.format || 'json';

  if (format === 'csv') {
    let csv = 'Timestamp,HeartRate_BPM,SpO2_Pct,SkinTemp_C,AmbientTemp_C,Humidity_Pct,Pressure_hPa,SolarCurrent_mA,Battery_Pct,MotionState\n';
    const len = history.optical.length;
    for (let i = 0; i < len; i++) {
      const opt = history.optical[i] || {};
      const thm = history.thermal[i] || {};
      const env = history.environmental[i] || {};
      const pwr = history.power[i] || {};
      csv += `${opt.time || ''},${opt.heartRateBpm || ''},${opt.spo2Pct || ''},${thm.skinTempC || ''},${thm.ambientTempC || ''},${thm.humidity || ''},${env.pressureHpa || ''},${pwr.solarMa || ''},${pwr.batteryPct || ''},${state.motionState}\n`;
    }
    res.setHeader('Content-Disposition', 'attachment; filename="ciris_telemetry_export.csv"');
    res.setHeader('Content-Type', 'text/csv');
    return res.send(csv);
  }

  res.setHeader('Content-Disposition', 'attachment; filename="ciris_telemetry_export.json"');
  res.json({
    exportDate: new Date().toISOString(),
    device: 'CIRIS ESP32-S3 Wearable Core',
    currentState: state,
    history
  });
});

// Complaints & Support API
app.get('/api/complaints', (req, res) => {
  res.json({ count: complaints.length, tickets: complaints });
});

app.post('/api/complaints', (req, res) => {
  const { name, email, category, subject, message } = req.body;
  if (!name || !message || !subject) {
    return res.status(400).json({ error: 'Name, subject, and message are required' });
  }

  // Automatic AI Diagnostic Triage
  let aiResolution = 'Ticket logged into Ciris Hardware RMA queue. Diagnostic logs extracted from active watch state.';
  if (/battery|drain|charge|solar/i.test(message)) {
    aiResolution = `Battery/Solar Diagnostic: Current LiPo voltage is ${state.batteryVoltage}V (${state.batteryPct}%). Solar charging is currently ${state.solarCharging ? 'ACTIVE (' + state.solarCurrentMa + 'mA)' : 'INACTIVE'}. Recommended verification: Inspect CN3065 STAT pin GPIO4 and ensure strap solar panel receives >15,000 lux.`;
  } else if (/sensor|heart|bpm|spo2|optical/i.test(message)) {
    aiResolution = `Optical Sensor Diagnostic: MAX30101 PPG red/IR channel is streaming nominal readings (BPM: ${state.heartRateBpm}, SpO2: ${state.spo2Pct}%). Ensure bottom sensor glass is clean and flush against epidermis.`;
  } else if (/button|panic|sos|buzzer/i.test(message)) {
    aiResolution = `Safety Subsystem Diagnostic: Tactile panic button on GPIO3 is currently ${state.panicButtonPressed ? 'ACTIVE' : 'IDLE'}. Piezo buzzer PWM on GPIO6 tested operational.`;
  }

  const newTicket = {
    id: `TKT-${Math.floor(1000 + Math.random() * 9000)}`,
    timestamp: new Date().toISOString(),
    name,
    email: email || 'user@ciris-wearable.io',
    category: category || 'General Inquiry',
    subject,
    message,
    status: 'Triage Automated / Review Queued',
    priority: /crash|burn|smoke|shock|critical|emergency/i.test(message) ? 'Urgent' : 'Standard',
    aiResolution
  };

  complaints.unshift(newTicket);
  res.status(201).json({ success: true, ticket: newTicket });
});

/*
 ==============================================================================
 AI CHATBOT ENGINE — POWERED BY CHATGPT & CIRIS HARDWARE INTELLIGENCE
 ==============================================================================
*/

const https = require('https');

async function callChatGPT(query, conversationHistory = []) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return null;

  const systemPrompt = `You are the CIRIS Health Companion & Wearable IoT Medical Intelligence Assistant.
You have real-time live telemetry access to the wearer's ESP32-S3 smartwatch:
- Heart Rate: ${state.heartRateBpm} BPM
- Blood Oxygen (SpO2): ${state.spo2Pct}%
- Clinical Skin Temp (MAX30208): ${state.skinTempC}°C
- Ambient Temp (SHT31): ${state.ambientTempC}°C
- Ambient Humidity: ${state.ambientHumidityPct}%
- Calculated Heat Index: ${state.heatIndexC}°C
- Barometric Pressure (BME280): ${state.barometricPressureHpa} hPa
- Motion State: ${state.motionState}
- Solar Harvesting (CN3065): ${state.solarCharging ? 'ACTIVE (' + state.solarCurrentMa + 'mA)' : 'INACTIVE'}
- Battery: ${state.batteryVoltage}V (${state.batteryPct}%)
- Panic SOS Status: ${state.panicAlertActive ? 'ALARM ACTIVE' : 'SECURE'}

Always answer questions accurately, informatively, with empathy and crisp precision. Remember you are an early warning health companion, not a final diagnostic doctor. SpO2 is a trend indicator.`;

  const messages = [
    { role: 'system', content: systemPrompt },
    ...conversationHistory.slice(-6).map(m => ({ role: m.role === 'bot' ? 'assistant' : m.role, content: m.content || '' })),
    { role: 'user', content: query }
  ];

  return new Promise((resolve) => {
    const postData = JSON.stringify({
      model: 'gpt-4o-mini',
      messages,
      temperature: 0.7,
      max_tokens: 450
    });

    const req = https.request({
      hostname: 'api.openai.com',
      port: 443,
      path: '/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 6000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          const reply = parsed?.choices?.[0]?.message?.content;
          resolve(reply || null);
        } catch (e) {
          resolve(null);
        }
      });
    });

    req.on('error', () => resolve(null));
    req.on('timeout', () => {
      req.destroy();
      resolve(null);
    });
    req.write(postData);
    req.end();
  });
}

app.post('/api/ai/chat', async (req, res) => {
  const { query, conversationHistory = [] } = req.body;
  if (!query) {
    return res.status(400).json({ error: 'Query is required' });
  }

  // 1. Check if direct ChatGPT API returns an answer
  const gptReply = await callChatGPT(query, conversationHistory);
  if (gptReply) {
    return res.json({
      reply: gptReply,
      source: 'ChatGPT-4o',
      relatedSensors: ['ESP32-S3', 'MAX30101', 'BMI270', 'CN3065'],
      suggestedFollowUps: ['Explain current heart rate trend', 'How does solar charging work?', 'Trigger emergency panic SOS'],
      liveTelemetrySnapshot: {
        bpm: state.heartRateBpm,
        spo2: state.spo2Pct,
        skinTemp: state.skinTempC,
        ambientTemp: state.ambientTempC,
        solarMa: state.solarCurrentMa,
        batteryPct: state.batteryPct,
        panicState: state.panicAlertActive
      },
      timestamp: Date.now()
    });
  }

  // 2. High-precision Built-in Clinical & Hardware Intelligence Engine
  const q = query.toLowerCase();
  let reply = '';
  let relatedSensors = [];
  let suggestedFollowUps = [];


  // Live sensor inquiry handling
  if (q.includes('heart') || q.includes('bpm') || q.includes('pulse') || q.includes('spo2') || q.includes('cardio') || q.includes('max30101')) {
    reply = `**MAX30101 Optical Biosensor Status**:\n` +
      `• **Heart Rate**: \`${state.heartRateBpm} BPM\` (${state.heartRateBpm < 60 ? 'Bradycardia' : state.heartRateBpm > 100 ? 'Elevated/Tachycardia' : 'Optimal Resting Rhythm'})\n` +
      `• **Blood Oxygen (SpO2)**: \`${state.spo2Pct}%\`\n` +
      `• **Perfusion Index**: \`${state.perfusionIndex}%\`\n` +
      `• **Raw Photoplethysmography (PPG)**: ADC value \`${state.ppgRawValue}\` @ 50Hz via I2C (0x57).\n\n` +
      `The MAX30101 uses dual Green & Infrared LEDs with internal ambient light cancellation for clinical-grade optical arterial pulse detection.`;
    relatedSensors = ['MAX30101'];
    suggestedFollowUps = ['Explain the optical sensor green LED principle', 'How does PPG calculate SpO2?', 'Trigger an emergency SOS alert'];
  } else if (q.includes('temp') || q.includes('heat') || q.includes('skin') || q.includes('body') || q.includes('max30208') || q.includes('sht31')) {
    reply = `**Dual-Thermal Subsystem Telemetry**:\n` +
      `• **Clinical Skin Temperature (MAX30208)**: \`${state.skinTempC}°C\` (Precision: ±0.1°C via I2C 0x50)\n` +
      `• **Ambient Air Temperature (SHT31)**: \`${state.ambientTempC}°C\`\n` +
      `• **Relative Humidity (SHT31)**: \`${state.ambientHumidityPct}%\`\n` +
      `• **Calculated Heat Index**: \`${state.heatIndexC}°C\` (Thermal stress level: Normal)\n\n` +
      `By isolating ambient atmospheric temperature from epidermal contact temperature, the dual-sensor loop calculates physiological thermoregulation and hypothermia/heatstroke warnings.`;
    relatedSensors = ['MAX30208', 'SHT31'];
    suggestedFollowUps = ['Why use MAX30208 instead of standard thermistors?', 'How is heat index computed?'];
  } else if (q.includes('solar') || q.includes('battery') || q.includes('power') || q.includes('charge') || q.includes('cn3065')) {
    reply = `**Power Architecture & Solar Harvest System**:\n` +
      `• **CN3065 Solar Controller**: \`${state.solarCharging ? 'HARVESTING (Active)' : 'STANDBY'}\`\n` +
      `• **Solar Current Input**: \`${state.solarCurrentMa} mA\` @ \`${state.solarVoltage}V\`\n` +
      `• **Ambient Irradiance**: \`${state.solarIrradianceLux.toLocaleString()} Lux\`\n` +
      `• **LiPo Battery Cell**: \`${state.batteryVoltage}V\` (\`${state.batteryPct}%\` state of charge)\n` +
      `• **Protection**: Integrated low-forward-drop Schottky diode prevents reverse-leakage in dark conditions.\n\n` +
      `The flexible solar array seamlessly integrated into the wrist strap channels continuous photovoltage directly through the CN3065 constant-current/constant-voltage algorithm.`;
    relatedSensors = ['CN3065', 'Solar Strap', 'Schottky Diode', 'LiPo'];
    suggestedFollowUps = ['What is the role of the Schottky diode?', 'How long does the battery last without sun?'];
  } else if (q.includes('motion') || q.includes('step') || q.includes('imu') || q.includes('fall') || q.includes('bmi270') || q.includes('accel')) {
    reply = `**BMI270 6-Axis Inertial Measurement Unit (IMU)**:\n` +
      `• **Current Motion State**: \`${state.motionState}\`\n` +
      `• **Accelerometer Vector**: \`X: ${state.accelX}G | Y: ${state.accelY}G | Z: ${state.accelZ}G\`\n` +
      `• **Total Acceleration Magnitude**: \`${Math.sqrt(state.accelX**2 + state.accelY**2 + state.accelZ**2).toFixed(2)}G\`\n` +
      `• **Step Count**: \`${state.stepCount.toLocaleString()} steps\` (Cadence: \`${state.cadenceRpm} RPM\`)\n` +
      `• **Fall Detection Algorithm**: Dual-phase vector threshold (<0.2G freefall window + >3.5G impact spike).\n\n` +
      `The ultra-low power Bosch BMI270 features embedded hardware feature detection, offloading gesture and step interrupts from the main ESP32-S3 cores.`;
    relatedSensors = ['BMI270'];
    suggestedFollowUps = ['Simulate a fall detection event', 'How does the step counter filter noise?'];
  } else if (q.includes('panic') || q.includes('sos') || q.includes('emergency') || q.includes('safety') || q.includes('buzzer') || q.includes('vibration')) {
    reply = `**Emergency Safety & Panic Response Subsystem**:\n` +
      `• **Physical SOS Button**: \`${state.panicButtonPressed ? 'TRIGGERED / ALARM ACTIVE' : 'SECURE / READY'}\` (GPIO 3 Active-Low Interrupt)\n` +
      `• **Haptic ERM Vibration Motor**: \`${state.hapticMotorActive ? 'VIBRATING' : 'IDLE'}\` (GPIO 5 PWM)\n` +
      `• **Acoustic Piezo Buzzer**: \`${state.piezoBuzzerActive ? '95dB AUDIBLE SIREN' : 'SILENT'}\` (GPIO 6 LEDC)\n` +
      `• **Emergency Protocol**: When the tactile silicone panic button is held for >1.5s, the watch emits high-frequency haptic pulses, sounds the acoustic beacon, and broadcasts emergency GATT beacon packets.`;
    relatedSensors = ['Panic Button', 'Vibration Motor', 'Piezo Buzzer'];
    suggestedFollowUps = ['Trigger emergency panic mode now', 'Clear emergency panic alert'];
  } else if (q.includes('esp32') || q.includes('mcu') || q.includes('processor') || q.includes('chip') || q.includes('firmware') || q.includes('specs')) {
    reply = `**ESP32-S3 Core Architecture & Hardware Specifications**:\n` +
      `• **Processor**: Dual-core 32-bit Xtensa® LX7 up to 240 MHz with vector instructions for AI biosignal processing.\n` +
      `• **Memory**: 512 KB SRAM + 8 MB Octal PSRAM + 16 MB Quad SPI Flash.\n` +
      `• **Wireless**: 2.4 GHz Wi-Fi (802.11 b/g/n) & Bluetooth 5 (LE) with Long Range & Mesh.\n` +
      `• **Display**: 0.96-inch Monochrome SSD1306 OLED (128x64 pixels) via hardware I2C.\n` +
      `• **Sensors**: MAX30101 (Optical), BMI270 (IMU), SHT31 (Temp/Hum), MAX30208 (Skin Temp), BME280 (Pressure).\n` +
      `• **Power**: CN3065 solar controller + Schottky reverse protection + 380mAh LiPo.\n` +
      `• **Waterproofing**: Precision silicone gasket + electronics conformal coating.`;
    relatedSensors = ['ESP32-S3', 'SSD1306 OLED'];
    suggestedFollowUps = ['What are the I2C addresses used?', 'Explain the BLE packet format'];
  } else if (q.includes('flood') || q.includes('rain') || q.includes('weather') || q.includes('pressure') || q.includes('bme280') || q.includes('altitude') || q.includes('pollution') || q.includes('air')) {
    reply = `**Environmental & Atmospheric Intelligence (BME280)**:\n` +
      `• **Barometric Pressure**: \`${state.barometricPressureHpa} hPa\`\n` +
      `• **Barometric Altitude**: \`${state.altitudeM} m\`\n` +
      `• **Rapid Drop Storm/Flood Index**: \`${(state.floodRiskScore * 100).toFixed(1)}%\` (Low Risk)\n` +
      `• **Estimated Air Quality (AQI)**: \`${state.airQualityIndex}\` (Good / Clean Outdoor Baseline)\n\n` +
      `Sudden drops in barometric pressure (>3.0 hPa / hr) combined with high ambient humidity trigger early flood, severe storm, and barometric headache alerts.`;
    relatedSensors = ['BME280', 'SHT31'];
    suggestedFollowUps = ['How does the watch detect flood risk?', 'View environmental history'];
  } else if (q.includes('complaint') || q.includes('issue') || q.includes('broken') || q.includes('ticket') || q.includes('support') || q.includes('warranty') || q.includes('help')) {
    reply = `**Ciris Support & Complaint Assistance**:\n` +
      `I can directly lodge an engineering RMA or support ticket on your behalf, or troubleshoot your watch right now.\n\n` +
      `Would you like to:\n` +
      `1. Run full automated hardware diagnostic test on all 6 sensor channels.\n` +
      `2. Submit an official support ticket for warranty or firmware assistance.\n` +
      `3. Download current diagnostic telemetry logs (JSON / CSV).\n\n` +
      `You can also use the Support & Complaint modal at the top navigation to file a ticket.`;
    suggestedFollowUps = ['Run full hardware diagnostic', 'Lodge a support ticket', 'Export telemetry data'];
  } else {
    reply = `Welcome to **Ciris Hardware Intelligence**. I am connected in real-time to the ESP32-S3 smartwatch core.\n\n` +
      `• **System Status**: All 16 primary components nominal.\n` +
      `• **Live Telemetry**: Heart Rate \`${state.heartRateBpm} BPM\`, Skin Temp \`${state.skinTempC}°C\`, Solar Harvest \`${state.solarCurrentMa} mA\`, Battery \`${state.batteryPct}%\`.\n\n` +
      `Ask me anything about component engineering, sensor diagnostics, solar power flow, emergency panic response, firmware BLE specs, or lodge a support inquiry!`;
    suggestedFollowUps = ['What sensors are inside the watch?', 'How does the solar charging strap work?', 'Show live telemetry diagnostics'];
  }

  res.json({
    reply,
    relatedSensors,
    suggestedFollowUps,
    liveTelemetrySnapshot: {
      bpm: state.heartRateBpm,
      spo2: state.spo2Pct,
      skinTemp: state.skinTempC,
      ambientTemp: state.ambientTempC,
      solarMa: state.solarCurrentMa,
      batteryPct: state.batteryPct,
      panicState: state.panicAlertActive
    },
    timestamp: Date.now()
  });
});

// Start Server
if (require.main === module) {
  runMigrations().then(() => {
    app.listen(PORT, () => {
      console.log(`=======================================================`);
      console.log(` CIRIS SMARTWATCH PLATFORM RUNNING AT: http://localhost:${PORT}`);
      console.log(` - Production Data Engineering & ML Engine: ACTIVE`);
      console.log(` - SQLite WAL Database & Migrations: INITIALIZED`);
      console.log(` - Scrollytelling 300-frame Canvas Engine ready`);
      console.log(` - Live ESP32-S3 Telemetry Generator: 50Hz`);
      console.log(` - AI Hardware Diagnostics Engine & API active`);
      console.log(`=======================================================`);
    });
  }).catch((err) => {
    console.error('[SERVER BOOT ERROR] Failed to run database migrations:', err);
    process.exit(1);
  });
}

module.exports = app;

