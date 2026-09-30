/* ==============================================================================
   CIRIS PERSONALIZATION ENGINE & CLINICAL HEALTH PROFILE v3
   Personal baselines, Health Score Ring, Wearer Profile, Emergency Escalation,
   Settings Drawer, Theme Engine, and Number Tweening
   ============================================================================== */

(function () {
  'use strict';

  // 1. Wearer Profile & Baselines Defaults
  const DEFAULT_PROFILE = {
    name: 'Monish Nawaz',
    email: 'monishnawaz02@gmail.com',
    bandId: 'CIRIS-S3-8942',
    role: 'wearer', // 'wearer', 'caregiver', 'engineer'
    baselines: {
      restingHr: 68,
      typicalSpo2: 98.4,
      baselineSkinTemp: 34.2
    },
    emergencyContacts: [
      { priority: 1, name: 'Dr. Sarah Rostova', relation: 'Primary Caregiver', phone: '+91 98765 43210' },
      { priority: 2, name: 'Marcus Vance', relation: 'Workplace Safety Lead', phone: '+91 98765 43211' },
      { priority: 3, name: 'Municipal Rescue Dispatch', relation: 'Emergency Services (112 Fallback)', phone: '112' }
    ],
    settings: {
      theme: 'dark',
      tempUnit: 'C', // 'C' or 'F'
      altUnit: 'm', // 'm' or 'ft'
      density: 'comfortable', // 'comfortable' or 'compact'
      soundEnabled: true,
      reducedMotion: false,
      activePreset: 'wellness' // 'wellness', 'outdoor', 'caregiver', 'engineer'
    }
  };

  // Load from localStorage/sessionStorage
  let profile = (function loadProfile() {
    try {
      const saved = localStorage.getItem('ciris_wearer_profile');
      if (saved) return JSON.parse(saved);
    } catch (_) {}
    return DEFAULT_PROFILE;
  })();

  // Synchronize emergency contacts if stored from auth modal
  try {
    const authContacts = sessionStorage.getItem('ciris_emergency_contacts');
    if (authContacts) {
      const parsed = JSON.parse(authContacts);
      if (Array.isArray(parsed) && parsed.length > 0) {
        profile.emergencyContacts = parsed.map((c, i) => ({
          priority: c.priority || i + 1,
          name: c.name || `Contact ${i + 1}`,
          relation: i === 0 ? 'Primary Caregiver' : (i === 1 ? 'Secondary Contact' : 'Emergency 112'),
          phone: c.phone || '112'
        }));
      }
    }
    const authEmail = sessionStorage.getItem('ciris_user_email');
    if (authEmail && authEmail !== 'demo@ciris-guardian.io') {
      profile.email = authEmail;
      profile.name = authEmail.split('@')[0].replace(/[._-]/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }
  } catch (_) {}

  function saveProfile() {
    try {
      localStorage.setItem('ciris_wearer_profile', JSON.stringify(profile));
    } catch (_) {}
  }

  // 2. Greeting Calculation
  function getGreeting() {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // 3. Number Tweening Utility for buttery transitions
  const activeTweens = {};
  window.tweenNumber = function (elementId, targetValue, decimals = 0, suffix = '', prefix = '') {
    const el = document.getElementById(elementId);
    if (!el) return;

    if (activeTweens[elementId]) {
      cancelAnimationFrame(activeTweens[elementId].rafId);
    }

    const currentText = el.textContent.replace(/[^0-9.-]/g, '');
    const startValue = parseFloat(currentText) || targetValue;
    const startTime = performance.now();
    const duration = 220; // 220ms smooth tween

    function step(now) {
      const progress = Math.min((now - startTime) / duration, 1.0);
      const ease = 1 - Math.pow(1 - progress, 3); // cubic ease out
      const val = startValue + (targetValue - startValue) * ease;
      el.textContent = `${prefix}${val.toFixed(decimals)}${suffix}`;

      if (progress < 1.0) {
        activeTweens[elementId] = { rafId: requestAnimationFrame(step) };
      }
    }

    activeTweens[elementId] = { rafId: requestAnimationFrame(step) };
  };

  // 4. Update Wearer Header & Personal Baselines
  window.updateWearerHeader = function () {
    const greetingEl = document.getElementById('wearer-greeting');
    const nameEl = document.getElementById('wearer-name');
    const avatarInitialsEl = document.getElementById('wearer-avatar-initials');
    const bandIdEl = document.getElementById('wearer-band-id');
    const lastSyncEl = document.getElementById('wearer-last-sync');

    if (greetingEl) greetingEl.textContent = getGreeting();
    if (nameEl) nameEl.textContent = profile.name || 'Monish Nawaz';
    if (avatarInitialsEl) {
      const names = (profile.name || 'MN').split(' ');
      const initials = names.length > 1 ? names[0][0] + names[1][0] : names[0].slice(0, 2);
      avatarInitialsEl.textContent = initials.toUpperCase();
    }
    if (bandIdEl) bandIdEl.textContent = profile.bandId || 'CIRIS-S3-8942';
    if (lastSyncEl) {
      const now = new Date();
      lastSyncEl.textContent = `Synced ${now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
    }
  };

  // 5. Compute Health Score & Plain Language Insight
  window.computeHealthScore = function (telemetry) {
    if (!telemetry) return;
    const hr = telemetry.heartRateBpm || 72;
    const spo2 = telemetry.spo2Pct || 98.4;
    const skinT = telemetry.skinTempC || 34.2;
    const flood = telemetry.floodRiskScore || 0.04;
    const hrDeviation = hr - profile.baselines.restingHr;

    // Deduct score for hypoxia or excessive tachycardia
    let score = 100;
    if (spo2 < 95) score -= (95 - spo2) * 5;
    if (hr > 100) score -= (hr - 100) * 0.8;
    if (hr < 45) score -= (45 - hr) * 1.5;
    if (skinT > 37.5) score -= (skinT - 37.5) * 8;
    if (flood > 0.4) score -= (flood * 20);
    if (telemetry.panicAlertActive) score = 12;
    score = Math.max(8, Math.min(100, Math.round(score)));

    // Update Ring
    const scoreValEl = document.getElementById('health-score-value');
    const scoreCircleEl = document.getElementById('health-score-circle');
    const insightEl = document.getElementById('health-score-insight');

    if (scoreValEl) window.tweenNumber('health-score-value', score, 0);
    if (scoreCircleEl) {
      const circumference = 2 * Math.PI * 40; // r=40
      const strokeDashoffset = circumference - (score / 100) * circumference;
      scoreCircleEl.style.strokeDashoffset = strokeDashoffset;
      scoreCircleEl.style.stroke = score > 85 ? '#10b981' : (score > 65 ? '#f59e0b' : '#ef4444');
    }

    // Baseline Deviations
    const hrDevEl = document.getElementById('hr-baseline-dev');
    if (hrDevEl) {
      const sign = hrDeviation >= 0 ? '+' : '';
      hrDevEl.textContent = `${sign}${hrDeviation} bpm vs usual`;
      hrDevEl.className = Math.abs(hrDeviation) > 15 ? 'delta-pill delta-elevated' : 'delta-pill delta-nominal';
    }

    const spo2DevEl = document.getElementById('spo2-baseline-dev');
    if (spo2DevEl) {
      const dev = (spo2 - profile.baselines.typicalSpo2).toFixed(1);
      spo2DevEl.textContent = `${dev >= 0 ? '+' : ''}${dev}% vs usual`;
    }

    // Plain Language Insight
    if (insightEl) {
      if (telemetry.panicAlertActive) {
        insightEl.textContent = '🚨 Emergency SOS Beacon engaged. Medical escalation in progress.';
      } else if (telemetry.motionState === 'FALL_DETECTED') {
        insightEl.textContent = '⚠️ Severe impact detected. Check wearer responsiveness.';
      } else if (spo2 < 92) {
        insightEl.textContent = 'Oxygen saturation below nominal range. Sit upright and breathe deeply.';
      } else if (hrDeviation > 20) {
        insightEl.textContent = 'Heart rate is elevated above your resting baseline — observing recovery.';
      } else if (telemetry.solarCharging) {
        insightEl.textContent = 'Optimal energy harvesting active. Solar strap keeping LiPo topped up.';
      } else {
        insightEl.textContent = 'All cardiovascular and environmental biomarkers are optimal.';
      }
    }
  };

  // 6. Render Emergency Contacts Escalation Chain
  window.renderEmergencyContacts = function () {
    const listEl = document.getElementById('emergency-contacts-list');
    if (!listEl) return;

    listEl.innerHTML = profile.emergencyContacts.map(c => `
      <div class="escalation-item priority-${c.priority}">
        <div class="escalation-prio-badge">P${c.priority}</div>
        <div class="escalation-info">
          <div class="escalation-name">${c.name}</div>
          <div class="escalation-sub">${c.relation} · ${c.phone}</div>
        </div>
        <div class="escalation-actions">
          <a href="tel:${c.phone}" class="esc-btn" title="Call Contact"><i data-lucide="phone"></i></a>
          <a href="sms:${c.phone}" class="esc-btn" title="SMS Alert"><i data-lucide="message-square"></i></a>
        </div>
      </div>
    `).join('');

    if (window.lucide) window.lucide.createIcons();
  };

  // 7. Role Preset Selector
  window.setDashboardPreset = function (presetName) {
    profile.settings.activePreset = presetName;
    saveProfile();

    document.querySelectorAll('.preset-tab-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.preset === presetName);
    });

    const bento = document.getElementById('telemetry-bento');
    if (bento) {
      bento.className = `bento-dashboard preset-${presetName}`;
    }
  };

  // 8. Settings Drawer Controls
  window.toggleSettingsDrawer = function () {
    const drawer = document.getElementById('settings-drawer');
    if (drawer) drawer.classList.toggle('open');
  };

  window.setTheme = function (theme) {
    profile.settings.theme = theme;
    saveProfile();
    document.documentElement.setAttribute('data-theme', theme);
    const themeBtn = document.getElementById('theme-toggle-btn');
    if (themeBtn) {
      themeBtn.innerHTML = theme === 'light'
        ? '<i data-lucide="moon"></i>'
        : '<i data-lucide="sun"></i>';
      if (window.lucide) window.lucide.createIcons();
    }
  };

  window.toggleTheme = function () {
    const newTheme = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    window.setTheme(newTheme);
  };

  window.updateTempUnit = function (unit) {
    profile.settings.tempUnit = unit;
    saveProfile();
    document.querySelectorAll('.temp-unit-label').forEach(el => el.textContent = `°${unit}`);
  };

  // Init on DOM ready
  document.addEventListener('DOMContentLoaded', () => {
    // Apply saved theme
    window.setTheme(profile.settings.theme || 'dark');
    window.updateWearerHeader();
    window.renderEmergencyContacts();
    window.setDashboardPreset(profile.settings.activePreset || 'wellness');
  });

  // Export profile object for external modules
  window.CirisProfile = {
    get: () => profile,
    update: (newP) => {
      profile = { ...profile, ...newP };
      saveProfile();
      window.updateWearerHeader();
      window.renderEmergencyContacts();
    }
  };
})();
