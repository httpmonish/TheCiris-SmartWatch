/*
 ==============================================================================
 CIRIS WATCH — TELEMETRY CONSOLE ENGINE v2
 60fps PPG Oscilloscope, Multi-Channel History Charts, SSE Live Stream
 ==============================================================================
*/

(function() {
  'use strict';

  let liveTelemetry = {};
  let historyCache  = {};
  let currentTab    = 'optical';

  const ppgCanvas  = document.getElementById('ppg-canvas');
  const ppgCtx     = ppgCanvas ? ppgCanvas.getContext('2d') : null;
  const ppgBuffer  = [];
  const MAX_PPG    = 120;
  for (let i = 0; i < MAX_PPG; i++) {
    const p = (i / MAX_PPG) * Math.PI * 6;
    ppgBuffer.push(Math.round(2048 + Math.sin(p * 2.2) * 260 + Math.sin(p * 4.4) * 110));
  }

  const histCanvas = document.getElementById('history-canvas');
  const histCtx    = histCanvas ? histCanvas.getContext('2d') : null;

  // Pre-seed history cache for immediate visual response
  (function initHistoryCache() {
    const now = Date.now();
    const channels = ['optical', 'motion', 'thermal', 'environmental', 'power'];
    channels.forEach(ch => {
      historyCache[ch] = [];
      for (let i = 60; i >= 0; i--) {
        const t = new Date(now - i * 2000).toISOString();
        const p = (60 - i) * 0.15;
        if (ch === 'optical') {
          historyCache[ch].push({ time: t, heartRateBpm: Math.round(71 + Math.sin(p) * 6), spo2Pct: +(98.4 + Math.cos(p * 0.5) * 0.4).toFixed(1) });
        } else if (ch === 'motion') {
          historyCache[ch].push({ time: t, accelMagnitude: +(1.02 + Math.sin(p * 2) * 0.18).toFixed(2), stepCount: 8400 + (60 - i) * 2 });
        } else if (ch === 'thermal') {
          historyCache[ch].push({ time: t, skinTempC: +(34.3 + Math.sin(p * 0.4) * 0.2).toFixed(1) });
        } else if (ch === 'environmental') {
          historyCache[ch].push({ time: t, pressureHpa: +(1013.2 + Math.cos(p * 0.3) * 0.5).toFixed(1) });
        } else if (ch === 'power') {
          historyCache[ch].push({ time: t, solarMa: +(28.0 + Math.sin(p * 0.8) * 4.5).toFixed(1) });
        }
      }
    });
  })();

  /* ------------------------------------------------------------------ */
  /* Canvas Sizing                                                        */
  /* ------------------------------------------------------------------ */
  function sizeChart(canvas) {
    if (!canvas) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const rect = canvas.getBoundingClientRect();
    const w = rect.width || canvas.clientWidth || canvas.parentElement?.clientWidth || 300;
    const h = rect.height || canvas.clientHeight || canvas.parentElement?.clientHeight || 95;
    if (w === 0 || h === 0) return;
    canvas.width  = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    const c = canvas.getContext('2d');
    if (c) {
      c.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
  }

  function initCharts() {
    sizeChart(ppgCanvas);
    sizeChart(histCanvas);
  }

  /* ------------------------------------------------------------------ */
  /* 60fps PPG Oscilloscope Render                                        */
  /* ------------------------------------------------------------------ */
  let wavePhase = 0;
  function renderPPG() {
    if (!ppgCtx || !ppgCanvas) return;
    const rect = ppgCanvas.getBoundingClientRect();
    const w = rect.width || ppgCanvas.clientWidth || 300;
    const h = rect.height || ppgCanvas.clientHeight || 95;
    if (w === 0 || h === 0) return;

    // Advance live oscilloscope waveform
    wavePhase += 0.08;
    const pulse = Math.sin(wavePhase * 2.2) * 0.6 + Math.sin(wavePhase * 4.4) * 0.25;
    const hr = liveTelemetry.heartRateBpm || 72;
    const ampl = 340 + (hr - 60) * 3;
    const waveVal = Math.round(2048 + pulse * ampl + (Math.random() - 0.5) * 20);
    ppgBuffer.push(waveVal);
    if (ppgBuffer.length > MAX_PPG) ppgBuffer.shift();

    ppgCtx.clearRect(0, 0, w, h);

    // Grid
    ppgCtx.strokeStyle = 'rgba(255,255,255,0.05)';
    ppgCtx.lineWidth = 1;
    for (let x = 0; x < w; x += 28) {
      ppgCtx.beginPath(); ppgCtx.moveTo(x, 0); ppgCtx.lineTo(x, h); ppgCtx.stroke();
    }
    for (let y = 0; y < h; y += 18) {
      ppgCtx.beginPath(); ppgCtx.moveTo(0, y); ppgCtx.lineTo(w, y); ppgCtx.stroke();
    }

    if (ppgBuffer.length < 2) return;

    // Gradient fill under wave
    const grad = ppgCtx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, 'rgba(0,214,255,0.35)');
    grad.addColorStop(1, 'rgba(0,214,255,0)');

    const stepX = w / (MAX_PPG - 1);
    const MIN_V = 1400, MAX_V = 2700, RANGE = MAX_V - MIN_V;

    ppgCtx.beginPath();
    for (let i = 0; i < ppgBuffer.length; i++) {
      const v    = ppgBuffer[i];
      const norm = Math.max(0, Math.min(1, (v - MIN_V) / RANGE));
      const py   = h - (norm * h * 0.80) - h * 0.08;
      const px   = i * stepX;
      if (i === 0) ppgCtx.moveTo(px, py); else ppgCtx.lineTo(px, py);
    }

    ppgCtx.strokeStyle = '#00D6FF';
    ppgCtx.lineWidth = 2;
    ppgCtx.shadowColor = '#00D6FF';
    ppgCtx.shadowBlur = 10;
    ppgCtx.stroke();
    ppgCtx.shadowBlur = 0;

    // Fill
    ppgCtx.lineTo(w, h); ppgCtx.lineTo(0, h); ppgCtx.closePath();
    ppgCtx.fillStyle = grad;
    ppgCtx.fill();
  }

  /* ------------------------------------------------------------------ */
  /* Historical Chart Render                                              */
  /* ------------------------------------------------------------------ */
  function renderHistory() {
    if (!histCtx || !histCanvas) return;
    const rect = histCanvas.getBoundingClientRect();
    const w = rect.width || histCanvas.clientWidth || 600;
    const h = rect.height || histCanvas.clientHeight || 220;
    if (w === 0 || h === 0) return;
    histCtx.clearRect(0, 0, w, h);

    // Grid
    histCtx.strokeStyle = 'rgba(255,255,255,0.05)';
    histCtx.lineWidth = 1;
    for (let y = 0; y < h; y += 40) {
      histCtx.beginPath(); histCtx.moveTo(0, y); histCtx.lineTo(w, y); histCtx.stroke();
    }
    for (let x = 0; x < w; x += 60) {
      histCtx.beginPath(); histCtx.moveTo(x, 0); histCtx.lineTo(x, h); histCtx.stroke();
    }

    const data = historyCache[currentTab] || [];
    if (data.length < 2) return;

    const config = {
      optical:       { key: 'heartRateBpm',     label: 'HEART RATE (BPM)',          color: '#00D6FF' },
      motion:        { key: 'accelMagnitude',    label: 'ACCELERATION MAGNITUDE (G)', color: '#0050FF' },
      thermal:       { key: 'skinTempC',         label: 'CLINICAL SKIN TEMP (°C)',    color: '#F59E0B' },
      environmental: { key: 'pressureHpa',       label: 'BAROMETRIC PRESSURE (hPa)',  color: '#22d3ee' },
      power:         { key: 'solarMa',           label: 'SOLAR HARVEST CURRENT (mA)', color: '#4ade80' }
    };

    const cfg = config[currentTab] || config.optical;
    let min = Infinity, max = -Infinity;
    data.forEach(d => {
      const v = d[cfg.key];
      if (v !== undefined) { if (v < min) min = v; if (v > max) max = v; }
    });

    if (!isFinite(min)) min = 60;
    if (!isFinite(max)) max = 100;
    const range = Math.max(max - min, 0.001);
    const stepX = w / (data.length - 1);

    // Area gradient
    const areaGrad = histCtx.createLinearGradient(0, 0, 0, h);
    areaGrad.addColorStop(0, cfg.color + '40');
    areaGrad.addColorStop(1, cfg.color + '00');

    histCtx.beginPath();
    let firstY = 0;
    for (let i = 0; i < data.length; i++) {
      const v  = data[i][cfg.key] !== undefined ? data[i][cfg.key] : min;
      const py = h - ((v - min) / range) * (h * 0.75) - h * 0.12;
      const px = i * stepX;
      if (i === 0) { histCtx.moveTo(px, py); firstY = py; } else histCtx.lineTo(px, py);
    }

    histCtx.strokeStyle = cfg.color;
    histCtx.lineWidth   = 2.5;
    histCtx.shadowColor = cfg.color;
    histCtx.shadowBlur  = 12;
    histCtx.stroke();
    histCtx.shadowBlur  = 0;

    // Fill
    histCtx.lineTo(w, h); histCtx.lineTo(0, h); histCtx.closePath();
    histCtx.fillStyle = areaGrad;
    histCtx.fill();

    // Label
    histCtx.fillStyle = 'rgba(255,255,255,0.75)';
    histCtx.font      = '11px "JetBrains Mono", monospace';
    histCtx.fillText(`${cfg.label}  MIN: ${min.toFixed(1)}  MAX: ${max.toFixed(1)}  [Live SQLite Sync]`, 14, 20);
  }

  /* ------------------------------------------------------------------ */
  /* DOM Update — Telemetry Cards                                         */
  /* ------------------------------------------------------------------ */
  function set(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  function updateDOM(d) {
    liveTelemetry = d;

    // Optical
    set('telemetry-bpm', d.heartRateBpm);
    set('telemetry-spo2', d.spo2Pct);
    set('telemetry-ppg-raw', d.ppgRawValue + ' ADC');
    set('telemetry-pi', d.perfusionIndex + '%');

    // Multi-Modal Trained ML Model Inference (Synchronized with 5 Million Dataset)
    const means = [93.79, 36.06, 96.28, 34.49, 25.89, 53.85, 2.75, 77.96, 1011.76, 0.12];
    const stds = [33.87, 20.41, 3.33, 1.90, 6.22, 12.19, 5.48, 61.70, 8.15, 0.19];
    const W = [
      [-0.388, -0.833, 1.218],
      [4.705, -1.290, -3.423],
      [2.474, 1.072, -3.547],
      [-0.389, 0.806, -0.404],
      [0.010, 0.239, -0.248],
      [0.678, -0.754, 0.080],
      [1.115, -1.868, 0.757],
      [0.152, 1.389, -1.552],
      [0.317, -1.336, 1.028],
      [-2.695, 1.401, 1.294]
    ];
    const biases = [4.387, 0.708, -5.095];

    // Compute raw Jerk from 3-axis accel
    const jerk = Math.abs(d.accelX) + Math.abs(d.accelY) + Math.abs((d.accelZ || 1.0) - 1.0);
    const rmssd = Math.max(8, Math.round(52 - (d.heartRateBpm - 70) * 0.45));
    const rawFeats = [
      d.heartRateBpm,
      rmssd,
      d.spo2Pct,
      d.skinTempC,
      d.ambientTempC,
      d.ambientHumidityPct,
      jerk,
      d.airQualityIndex,
      d.barometricPressureHpa,
      d.floodRiskScore
    ];

    // Z-score Normalization
    const normX = rawFeats.map((v, idx) => (v - means[idx]) / stds[idx]);

    // Forward pass: logits = normX * W + biases
    const logits = [0, 1, 2].map(c => {
      let sum = biases[c];
      for (let f = 0; f < 10; f++) {
        sum += normX[f] * W[f][c];
      }
      return sum;
    });

    // Softmax
    const maxL = Math.max(...logits);
    const expL = logits.map(l => Math.exp(l - maxL));
    const sumExp = expL.reduce((a, b) => a + b, 0);
    const probs = expL.map(e => e / sumExp);
    const sCardiac = probs[2];

    // Rule-based override logic per clinical specification
    let tier = 'GREEN';
    let tierTitle = 'Physiological & Environmental Status Nominal';
    let tierSub = `ML Anomaly Score: ${(sCardiac * 100).toFixed(2)}% — All biological and atmospheric vectors within safe thresholds`;

    if (d.panicAlertActive) {
      tier = 'RED';
      tierTitle = 'CRITICAL OVERRIDE: Emergency Panic Button Depressed';
      tierSub = 'Immediate alert dispatched — Audio beacon and haptic response engaged';
    } else if (d.motionState === 'FALL_DETECTED') {
      tier = 'RED';
      tierTitle = 'CRITICAL OVERRIDE: Traumatic Freefall & Impact Detected';
      tierSub = 'Biomechanical fall vector registered (>3.2G impact)';
    } else if (d.spo2Pct < 90.0) {
      tier = 'RED';
      tierTitle = 'CRITICAL OVERRIDE: Severe Hypoxia Detected (SpO2 < 90%)';
      tierSub = 'Critical oxygen desaturation requires urgent intervention';
    } else if (sCardiac >= 0.70 || d.heatIndexC >= 41.0 || d.floodRiskScore >= 0.75) {
      tier = 'ORANGE';
      tierTitle = 'WARNING ORANGE: Elevated Multi-Modal Strain';
      tierSub = 'Early warning indicator — high heat, cardiac drift, or flood hazard';
    } else if (sCardiac >= 0.35 || d.spo2Pct < 94.0 || d.heatIndexC >= 32.0) {
      tier = 'YELLOW';
      tierTitle = 'CAUTION YELLOW: Mild Physiological or Environmental Elevation';
      tierSub = 'Moderate hypoxia or climate stress detected — monitoring trends';
    }

    const bannerEl = document.getElementById('ml-risk-tier-banner');
    const badgeEl = document.getElementById('ml-risk-badge');
    const nameEl = document.getElementById('ml-risk-tier-name');
    const titleEl = document.getElementById('ml-risk-title');
    const subEl = document.getElementById('ml-risk-sub');
    const p2El = document.getElementById('ml-risk-p2');
    const compEl = document.getElementById('ml-risk-composite');

    if (bannerEl) {
      bannerEl.className = 'ml-risk-banner tier-' + tier.toLowerCase() + ' reveal in-view';
    }
    if (nameEl) nameEl.textContent = tier + ' TIER';
    if (titleEl) titleEl.textContent = tierTitle;
    if (subEl) subEl.textContent = tierSub;
    if (p2El) p2El.textContent = (sCardiac * 100).toFixed(2) + '%';
    if (compEl) {
      const compScore = Math.min(1.0, (sCardiac * 0.4) + (d.floodRiskScore * 0.3) + (d.heatIndexC > 30 ? 0.3 : 0.05));
      compEl.textContent = compScore.toFixed(3);
    }

    // AI context strip
    set('ai-mini-bpm', d.heartRateBpm + ' BPM');
    set('ai-mini-temp', d.skinTempC + '°C');
    set('ai-mini-solar', d.solarCurrentMa + 'mA');


    // PPG buffer
    ppgBuffer.push(d.ppgRawValue);
    if (ppgBuffer.length > MAX_PPG) ppgBuffer.shift();

    // Motion
    set('telemetry-accel-x', (d.accelX >= 0 ? '+' : '') + d.accelX + 'G');
    set('telemetry-accel-y', (d.accelY >= 0 ? '+' : '') + d.accelY + 'G');
    set('telemetry-accel-z', (d.accelZ >= 0 ? '+' : '') + d.accelZ + 'G');
    set('telemetry-steps', d.stepCount.toLocaleString());
    set('telemetry-cadence', d.cadenceRpm);
    set('motion-badge', d.motionState);

    // Thermal
    set('telemetry-skin-temp', d.skinTempC);
    set('telemetry-ambient-temp', d.ambientTempC);
    set('telemetry-humidity', d.ambientHumidityPct + '%');
    const hiRisk = d.heatIndexC > 32 ? 'Caution' : 'Normal';
    set('telemetry-heat-index', d.heatIndexC + '°C (' + hiRisk + ')');

    // Environment
    set('telemetry-pressure', d.barometricPressureHpa);
    set('telemetry-altitude', d.altitudeM);
    const floodPct = (d.floodRiskScore * 100).toFixed(1);
    const floodRisk = d.floodRiskScore > 0.5 ? 'HIGH ALERT' : 'Stable';
    set('telemetry-flood', floodPct + '% (' + floodRisk + ')');
    const aqiLabel = d.airQualityIndex > 100 ? 'Moderate' : 'Good';
    set('telemetry-aqi', d.airQualityIndex + ' (' + aqiLabel + ')');
    const floodBar = document.getElementById('flood-bar');
    if (floodBar) floodBar.style.width = Math.min(100, d.floodRiskScore * 100) + '%';

    // Power
    set('telemetry-solar-ma', d.solarCurrentMa);
    set('telemetry-battery-pct', d.batteryPct);
    set('telemetry-battery-v', d.batteryVoltage + ' V');
    set('telemetry-lux', (d.solarIrradianceLux || 48500).toLocaleString() + ' Lux');
    const battBar = document.getElementById('battery-bar');
    if (battBar) battBar.style.width = d.batteryPct + '%';

    const solarBadge = document.getElementById('solar-stat-badge');
    if (solarBadge) {
      solarBadge.textContent = d.solarCharging ? 'HARVESTING' : 'STANDBY';
      solarBadge.className   = d.solarCharging
        ? 'tcard-badge tcard-badge-amber'
        : 'tcard-badge';
    }

    // Panic / Safety
    const panicCard  = document.getElementById('panic-card');
    const panicBtnTx = document.getElementById('panic-btn-text');
    const panicBadge = document.getElementById('panic-status-badge');
    const hapticEl   = document.getElementById('haptic-status');
    const buzzerEl   = document.getElementById('buzzer-status');
    const gattEl     = document.getElementById('gatt-sos-status');

    if (d.panicAlertActive) {
      panicCard && panicCard.classList.add('panic-active');
      panicBtnTx && (panicBtnTx.textContent = 'CLEAR EMERGENCY PANIC');
      if (panicBadge) { panicBadge.textContent = 'ALARM ACTIVE'; panicBadge.className = 'tcard-badge tcard-badge-red'; }
      if (hapticEl)  { hapticEl.textContent = 'VIBRATING (PWM)';  hapticEl.style.color = '#f87171'; }
      if (buzzerEl)  { buzzerEl.textContent = '95dB SIREN ACTIVE'; buzzerEl.style.color = '#f87171'; }
      if (gattEl)    { gattEl.textContent   = 'GATT: BROADCASTING SOS'; gattEl.style.color = '#f87171'; }
    } else {
      panicCard && panicCard.classList.remove('panic-active');
      panicBtnTx && (panicBtnTx.textContent = 'TRIGGER EMERGENCY PANIC');
      if (panicBadge) { panicBadge.textContent = 'SECURE'; panicBadge.className = 'tcard-badge tcard-badge-green'; }
      if (hapticEl)  { hapticEl.textContent = 'STANDBY';  hapticEl.style.color = 'rgba(255,255,255,0.8)'; }
      if (buzzerEl)  { buzzerEl.textContent = 'SILENT';   buzzerEl.style.color = 'rgba(255,255,255,0.8)'; }
      if (gattEl)    { gattEl.textContent   = 'GATT: Idle'; gattEl.style.color = '#4ade80'; }
    }
  }

  /* ------------------------------------------------------------------ */
  /* SSE Live Stream                                                      */
  /* ------------------------------------------------------------------ */
  function initStream() {
    if (typeof EventSource !== 'undefined') {
      const src = new EventSource('/api/telemetry/stream');
      src.onmessage = (e) => {
        try { updateDOM(JSON.parse(e.data)); } catch (_) {}
      };
      src.onerror = () => {
        src.close();
        setTimeout(pollFallback, 1000);
      };
    } else {
      setInterval(pollFallback, 200);
    }
  }

  function pollFallback() {
    fetch('/api/telemetry/live')
      .then(r => r.json())
      .then(res => { if (res.telemetry) updateDOM(res.telemetry); })
      .catch(() => {});
  }

  /* ------------------------------------------------------------------ */
  /* History Fetch                                                        */
  /* ------------------------------------------------------------------ */
  function fetchHistory() {
    fetch('/api/telemetry/history')
      .then(r => r.json())
      .then(res => {
        if (res.channels) { historyCache = res.channels; renderHistory(); }
      })
      .catch(() => {});
  }

  /* ------------------------------------------------------------------ */
  /* Public API                                                           */
  /* ------------------------------------------------------------------ */
  window.switchHistoryTab = function(tab, ev) {
    currentTab = tab;
    document.querySelectorAll('.hist-tab').forEach(b => {
      b.classList.remove('hist-tab-active');
    });
    if (ev && ev.target) ev.target.classList.add('hist-tab-active');
    renderHistory();
  };

  window.togglePanicState = function() {
    const action = liveTelemetry.panicAlertActive ? 'CLEAR_PANIC' : 'TRIGGER_PANIC';
    fetch('/api/telemetry/simulate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action })
    }).catch(() => {});
  };

  window.injectMotion = function(mode) {
    fetch('/api/telemetry/simulate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'SET_MOTION_MODE', payload: { mode } })
    }).catch(() => {});
  };

  window.injectSolar = function(charging, lux) {
    fetch('/api/telemetry/simulate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'TOGGLE_SOLAR', payload: { charging, lux } })
    }).catch(() => {});
  };

  window.injectEnvironment = function(pressure, floodRisk, aqi) {
    fetch('/api/telemetry/simulate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'SET_ENVIRONMENT', payload: { pressure, floodRisk, aqi } })
    }).catch(() => {});
  };

  window.exportTelemetry = function(fmt) {
    window.location.href = '/api/telemetry/export?format=' + fmt;
  };

  /* ------------------------------------------------------------------ */
  /* 60fps Loop                                                           */
  /* ------------------------------------------------------------------ */
  function rafLoop() {
    renderPPG();
    requestAnimationFrame(rafLoop);
  }

  /* ------------------------------------------------------------------ */
  /* Init                                                                 */
  /* ------------------------------------------------------------------ */
  window.addEventListener('resize', initCharts);
  initCharts();
  initStream();
  fetchHistory();
  setInterval(fetchHistory, 4000);
  rafLoop();
})();
