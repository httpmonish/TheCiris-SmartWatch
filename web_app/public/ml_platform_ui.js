/* ==============================================================================
   CIRIS PRODUCTION ML & MULTI-DATASET PLATFORM INTERACTIVE CONTROLLER
   ============================================================================== */

window.switchMlTab = function(tabName) {
  const tabs = ['wisdm', 'kaggle', 'ciris'];
  tabs.forEach(t => {
    const btn = document.getElementById(`tab-btn-${t}`);
    const content = document.getElementById(`ml-content-${t}`);
    const card = document.getElementById(`card-${t}`);
    if (btn) btn.classList.toggle('active', t === tabName);
    if (content) content.style.display = (t === tabName) ? 'block' : 'none';
    if (card) card.classList.toggle('active', t === tabName);
  });
  if (window.lucide && window.lucide.createIcons) window.lucide.createIcons();
};

/* ------------------------------------------------------------------ */
/* 1. WISDM Smartwatch HAR Interactive Logic                          */
/* ------------------------------------------------------------------ */
const WISDM_PRESETS = {
  walking: { amag: 9.8, astd: 2.4, jerk: 1.5, gmag: 1.1, energy: 110, act: 'Walking', cat: 'Ambulation', conf: 92.4, top: [['Walking', 0.924], ['Stairs', 0.045], ['Jogging', 0.021]] },
  jogging: { amag: 14.5, astd: 5.8, jerk: 4.2, gmag: 2.6, energy: 240, act: 'Jogging', cat: 'Ambulation', conf: 96.8, top: [['Jogging', 0.968], ['Walking', 0.022], ['Dribbling', 0.010]] },
  brushing: { amag: 9.9, astd: 1.8, jerk: 1.6, gmag: 3.8, energy: 125, act: 'Brushing Teeth', cat: 'Daily Living', conf: 89.5, top: [['Brushing Teeth', 0.895], ['Typing', 0.062], ['Drinking', 0.031]] },
  sitting: { amag: 9.8, astd: 0.15, jerk: 0.08, gmag: 0.05, energy: 96, act: 'Sitting', cat: 'Sedentary', conf: 98.2, top: [['Sitting', 0.982], ['Standing', 0.014], ['Typing', 0.004]] },
  typing: { amag: 9.8, astd: 0.45, jerk: 0.35, gmag: 0.4, energy: 98, act: 'Typing', cat: 'Sedentary', conf: 91.0, top: [['Typing', 0.910], ['Sitting', 0.055], ['Writing', 0.025]] },
  drinking: { amag: 9.8, astd: 0.95, jerk: 0.75, gmag: 1.4, energy: 102, act: 'Drinking', cat: 'Eating & Drinking', conf: 88.0, top: [['Drinking', 0.880], ['Eating Soup', 0.075], ['Eating Pasta', 0.035]] }
};

window.setWisdmPreset = function(presetKey) {
  const p = WISDM_PRESETS[presetKey];
  if (!p) return;
  document.getElementById('range-wisdm-amag').value = p.amag;
  document.getElementById('range-wisdm-astd').value = p.astd;
  document.getElementById('range-wisdm-jerk').value = p.jerk;
  document.getElementById('range-wisdm-gmag').value = p.gmag;
  document.getElementById('range-wisdm-energy').value = p.energy;
  renderWisdmResult(p.act, p.cat, p.conf, p.top);
  updateWisdmLabels();
};

window.updateWisdmLive = function() {
  updateWisdmLabels();
  const amag = parseFloat(document.getElementById('range-wisdm-amag').value);
  const astd = parseFloat(document.getElementById('range-wisdm-astd').value);
  const jerk = parseFloat(document.getElementById('range-wisdm-jerk').value);
  const gmag = parseFloat(document.getElementById('range-wisdm-gmag').value);

  let act = 'Walking';
  let cat = 'Ambulation';
  let conf = 88.5;
  let top = [];

  if (astd > 4.5 || jerk > 3.0) {
    act = 'Jogging'; cat = 'Ambulation'; conf = 95.2;
    top = [['Jogging', 0.952], ['Walking', 0.035], ['Dribbling', 0.013]];
  } else if (astd < 0.25 && gmag < 0.15) {
    act = 'Sitting'; cat = 'Sedentary'; conf = 97.4;
    top = [['Sitting', 0.974], ['Standing', 0.020], ['Typing', 0.006]];
  } else if (gmag > 2.5 && astd > 1.0) {
    act = 'Brushing Teeth'; cat = 'Daily Living'; conf = 90.1;
    top = [['Brushing Teeth', 0.901], ['Typing', 0.055], ['Drinking', 0.030]];
  } else if (astd < 0.7 && gmag < 0.6) {
    act = 'Typing'; cat = 'Sedentary'; conf = 89.6;
    top = [['Typing', 0.896], ['Sitting', 0.065], ['Writing', 0.028]];
  } else if (astd > 1.5) {
    act = 'Walking'; cat = 'Ambulation'; conf = 92.4;
    top = [['Walking', 0.924], ['Stairs', 0.051], ['Jogging', 0.025]];
  } else {
    act = 'Standing'; cat = 'Sedentary'; conf = 86.8;
    top = [['Standing', 0.868], ['Sitting', 0.082], ['Walking', 0.050]];
  }

  renderWisdmResult(act, cat, conf, top);
};

function updateWisdmLabels() {
  document.getElementById('val-wisdm-amag').textContent = document.getElementById('range-wisdm-amag').value;
  document.getElementById('val-wisdm-astd').textContent = document.getElementById('range-wisdm-astd').value;
  document.getElementById('val-wisdm-jerk').textContent = document.getElementById('range-wisdm-jerk').value;
  document.getElementById('val-wisdm-gmag').textContent = document.getElementById('range-wisdm-gmag').value;
  document.getElementById('val-wisdm-energy').textContent = document.getElementById('range-wisdm-energy').value;
}

function renderWisdmResult(act, cat, conf, top) {
  document.getElementById('wisdm-act-name').textContent = act;
  document.getElementById('wisdm-act-category').textContent = `Category: ${cat} · WISDM 18-Class HAR`;
  document.getElementById('wisdm-conf-pct').textContent = `${conf.toFixed(1)}%`;
  document.getElementById('wisdm-conf-fill').style.width = `${conf}%`;

  const topWrap = document.getElementById('wisdm-top-probs');
  if (topWrap && top) {
    topWrap.innerHTML = top.map(([name, prob]) => `
      <div class="prob-row">
        <span>${name}</span>
        <span class="prob-val">${(prob * 100).toFixed(1)}%</span>
      </div>
    `).join('');
  }
}

/* ------------------------------------------------------------------ */
/* 2. Kaggle Action Classifier Interactive Logic                      */
/* ------------------------------------------------------------------ */
const KAGGLE_PRESETS = {
  cycling: { edge: 28.5, vgrad: 14.5, sym: 0.82, cont: 42.0, name: 'Cycling', conf: 84.0, top: [['Cycling', 0.840], ['Running', 0.095], ['Fighting', 0.042]] },
  running: { edge: 45.0, vgrad: 24.0, sym: 0.65, cont: 55.0, name: 'Running', conf: 88.5, top: [['Running', 0.885], ['Dancing', 0.065], ['Cycling', 0.035]] },
  fighting: { edge: 62.0, vgrad: 32.0, sym: 0.52, cont: 68.0, name: 'Fighting', conf: 91.2, top: [['Fighting', 0.912], ['Dancing', 0.055], ['Running', 0.022]] },
  sitting: { edge: 15.0, vgrad: 8.5, sym: 0.88, cont: 24.0, name: 'Sitting', conf: 94.0, top: [['Sitting', 0.940], ['Sleeping', 0.042], ['Using Laptop', 0.015]] },
  sleeping: { edge: 10.0, vgrad: 5.0, sym: 0.92, cont: 18.0, name: 'Sleeping', conf: 96.5, top: [['Sleeping', 0.965], ['Sitting', 0.028], ['Hugging', 0.007]] },
  using_laptop: { edge: 22.0, vgrad: 12.0, sym: 0.79, cont: 34.0, name: 'Using Laptop', conf: 87.2, top: [['Using Laptop', 0.872], ['Sitting', 0.095], ['Calling', 0.025]] }
};

window.setKagglePreset = function(kKey) {
  const p = KAGGLE_PRESETS[kKey];
  if (!p) return;
  document.getElementById('range-kag-edge').value = p.edge;
  document.getElementById('range-kag-vgrad').value = p.vgrad;
  document.getElementById('range-kag-sym').value = p.sym;
  document.getElementById('range-kag-cont').value = p.cont;
  renderKaggleResult(p.name, p.conf, p.top);
  updateKaggleLabels();
};

window.updateKaggleLive = function() {
  updateKaggleLabels();
  const edge = parseFloat(document.getElementById('range-kag-edge').value);
  const sym = parseFloat(document.getElementById('range-kag-sym').value);

  let name = 'Cycling';
  let conf = 82.0;
  let top = [];

  if (edge > 50.0 && sym < 0.6) {
    name = 'Fighting'; conf = 89.5;
    top = [['Fighting', 0.895], ['Dancing', 0.065], ['Running', 0.025]];
  } else if (edge > 35.0) {
    name = 'Running'; conf = 86.4;
    top = [['Running', 0.864], ['Cycling', 0.082], ['Dancing', 0.034]];
  } else if (edge < 12.0) {
    name = 'Sleeping'; conf = 95.0;
    top = [['Sleeping', 0.950], ['Sitting', 0.038], ['Hugging', 0.012]];
  } else if (edge < 18.0 && sym > 0.8) {
    name = 'Sitting'; conf = 92.5;
    top = [['Sitting', 0.925], ['Sleeping', 0.052], ['Using Laptop', 0.018]];
  } else {
    name = 'Cycling'; conf = 84.0;
    top = [['Cycling', 0.840], ['Running', 0.095], ['Fighting', 0.042]];
  }

  renderKaggleResult(name, conf, top);
};

function updateKaggleLabels() {
  document.getElementById('val-kag-edge').textContent = document.getElementById('range-kag-edge').value;
  document.getElementById('val-kag-vgrad').textContent = document.getElementById('range-kag-vgrad').value;
  document.getElementById('val-kag-sym').textContent = document.getElementById('range-kag-sym').value;
  document.getElementById('val-kag-cont').textContent = document.getElementById('range-kag-cont').value;
}

function renderKaggleResult(name, conf, top) {
  document.getElementById('kag-act-name').textContent = name;
  document.getElementById('kag-conf-pct').textContent = `${conf.toFixed(1)}%`;
  document.getElementById('kag-conf-fill').style.width = `${conf}%`;

  const topWrap = document.getElementById('kag-top-probs');
  if (topWrap && top) {
    topWrap.innerHTML = top.map(([n, p]) => `
      <div class="prob-row">
        <span>${n}</span>
        <span class="prob-val">${(p * 100).toFixed(1)}%</span>
      </div>
    `).join('');
  }
}

/* ------------------------------------------------------------------ */
/* 3. CIRIS Risk Classifier Interactive Logic                         */
/* ------------------------------------------------------------------ */
window.setCirisPreset = function(type) {
  if (type === 'nominal') {
    document.getElementById('range-cir-hr').value = 58;
    document.getElementById('range-cir-spo2').value = 99.0;
    document.getElementById('range-cir-flood').value = 0.02;
  } else if (type === 'heat') {
    document.getElementById('range-cir-hr').value = 115;
    document.getElementById('range-cir-spo2').value = 95.5;
    document.getElementById('range-cir-flood').value = 0.35;
  } else {
    document.getElementById('range-cir-hr').value = 168;
    document.getElementById('range-cir-spo2').value = 84.0;
    document.getElementById('range-cir-flood').value = 0.88;
  }
  updateCirisLive();
};

window.updateCirisLive = function() {
  const hr = parseFloat(document.getElementById('range-cir-hr').value);
  const spo2 = parseFloat(document.getElementById('range-cir-spo2').value);
  const flood = parseFloat(document.getElementById('range-cir-flood').value);

  document.getElementById('val-cir-hr').textContent = `${hr} BPM`;
  document.getElementById('val-cir-spo2').textContent = `${spo2}%`;
  document.getElementById('val-cir-flood').textContent = flood.toFixed(2);

  let label = 'Nominal / Routine Baseline';
  let tier = 'Tier: NOMINAL_GREEN · 100k Sample Calibrated Model';
  let conf = 99.1;
  let color = '#10b981';
  let probs = [['Nominal Baseline', 0.991], ['Heat Strain', 0.007], ['Emergency Threat', 0.002]];

  if (spo2 < 90 || hr > 140 || flood > 0.7) {
    label = 'Life Emergency & Disaster Threat';
    tier = 'Tier: CRITICAL_RED · Urgent SOS Trigger Active';
    conf = 98.4;
    color = '#ef4444';
    probs = [['Emergency Threat', 0.984], ['Heat Strain', 0.012], ['Nominal Baseline', 0.004]];
  } else if (hr > 105 || spo2 < 95 || flood > 0.3) {
    label = 'Environmental & Heat Strain';
    tier = 'Tier: WARNING_ORANGE · Caution Advisory';
    conf = 92.5;
    color = '#f59e0b';
    probs = [['Heat Strain', 0.925], ['Emergency Threat', 0.055], ['Nominal Baseline', 0.020]];
  }

  document.getElementById('cir-risk-label').textContent = label;
  document.getElementById('cir-risk-tier').textContent = tier;
  document.getElementById('cir-conf-pct').textContent = `${conf.toFixed(1)}%`;
  document.getElementById('cir-conf-fill').style.width = `${conf}%`;
  document.getElementById('cir-conf-fill').style.background = color;

  const topWrap = document.getElementById('cir-top-probs');
  if (topWrap) {
    topWrap.innerHTML = probs.map(([n, p]) => `
      <div class="prob-row">
        <span>${n}</span>
        <span class="prob-val" style="color:${color}">${(p * 100).toFixed(1)}%</span>
      </div>
    `).join('');
  }
};

// Auto-init initial preset rendering on load
document.addEventListener('DOMContentLoaded', () => {
  setWisdmPreset('walking');
  setKagglePreset('cycling');
  setCirisPreset('nominal');
});
