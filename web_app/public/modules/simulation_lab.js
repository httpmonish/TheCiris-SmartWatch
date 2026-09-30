/* ==============================================================================
   CIRIS SIMULATION LAB & LIVE EVENT TIMELINE ENGINE v3
   Slide-out Simulation Drawer, Scenario Presets, Event Audit Log, Escalation Countdown
   ============================================================================== */

(function () {
  'use strict';

  let eventTimeline = [
    { time: new Date(Date.now() - 360000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }), type: 'system', title: 'BLE 5.0 GATT Stream Connected', desc: 'ESP32-S3 telemetry paired at 50Hz' },
    { time: new Date(Date.now() - 180000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }), type: 'power', title: 'Solar Harvest Active', desc: 'Strap array harvesting 28.4 mA under 48,500 Lux' },
    { time: new Date(Date.now() - 60000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }), type: 'nominal', title: 'Physiological Baseline Nominal', desc: 'Heart rate 72 BPM, SpO2 98.4%, Skin Temp 34.2°C' }
  ];

  let countdownInterval = null;

  window.toggleSimulationLab = function () {
    const drawer = document.getElementById('simulation-lab-drawer');
    if (drawer) drawer.classList.toggle('open');
  };

  // Add event to timeline and show toast
  window.logTimelineEvent = function (title, desc, type = 'info') {
    const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const ev = { time: timeStr, title, desc, type };
    eventTimeline.unshift(ev);
    if (eventTimeline.length > 50) eventTimeline.pop();

    renderTimeline();
    showToastNotification(title, desc, type);
  };

  function renderTimeline(filter = 'all') {
    const container = document.getElementById('timeline-events-container');
    if (!container) return;

    const filtered = filter === 'all' ? eventTimeline : eventTimeline.filter(e => e.type === filter);
    if (filtered.length === 0) {
      container.innerHTML = '<div class="timeline-empty">No events logged for this filter.</div>';
      return;
    }

    container.innerHTML = filtered.map(e => `
      <div class="timeline-event-item type-${e.type}">
        <div class="timeline-time">${e.time}</div>
        <div class="timeline-dot"></div>
        <div class="timeline-body">
          <div class="timeline-title">${e.title}</div>
          <div class="timeline-desc">${e.desc}</div>
        </div>
      </div>
    `).join('');
  }

  // Toast Notification
  function showToastNotification(title, message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `ciris-toast toast-${type}`;
    toast.innerHTML = `
      <div class="toast-icon">
        <i data-lucide="${type === 'critical' ? 'alert-triangle' : (type === 'warning' ? 'alert-circle' : 'info')}"></i>
      </div>
      <div class="toast-body">
        <div class="toast-title">${title}</div>
        <div class="toast-msg">${message}</div>
      </div>
      <button class="toast-close" onclick="this.parentElement.remove()"><i data-lucide="x"></i></button>
    `;
    container.appendChild(toast);
    if (window.lucide) window.lucide.createIcons();

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(-10px)';
      setTimeout(() => toast.remove(), 300);
    }, 4500);
  }

  // Simulation Lab Scenarios
  window.runSimulationScenario = function (scenarioKey) {
    if (scenarioKey === 'freefall') {
      window.injectMotion('FALL_DETECTED');
      window.logTimelineEvent('Traumatic Freefall & Impact', 'BMI270 freefall <0.2G followed by 4.2G wrist impact detected', 'critical');
      startEscalationCountdown('Fall impact confirmation');
    } else if (scenarioKey === 'storm') {
      window.injectEnvironment(965.0, 0.88, 120);
      window.logTimelineEvent('Flash Flood & Barometric Anomaly', 'Pressure dropped to 965 hPa with 88% microclimate flood threat', 'warning');
    } else if (scenarioKey === 'darkness') {
      window.injectSolar(false, 30);
      window.logTimelineEvent('Total Solar Deprivation', 'Solar strap transitioned to standby (<50 Lux). LiPo power mode: LOW_POWER', 'info');
    } else if (scenarioKey === 'heatwave') {
      fetch('/api/telemetry/simulate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'SET_ENVIRONMENT', payload: { temp: 42.5, humidity: 75.0, floodRisk: 0.25 } })
      }).catch(() => {});
      window.logTimelineEvent('Severe Heat Wave Strain', 'Epidermal and ambient heat index exceeded 43°C', 'warning');
    } else if (scenarioKey === 'nominal') {
      window.injectMotion('STEADY_WALK');
      window.injectSolar(true, 48500);
      window.injectEnvironment(1013.25, 0.04, 28);
      if (typeof window.togglePanicState === 'function') {
        fetch('/api/telemetry/simulate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'CLEAR_PANIC' })
        }).catch(() => {});
      }
      stopEscalationCountdown();
      window.logTimelineEvent('All Vectors Restored to Nominal', 'Cardiac, atmospheric, and motion metrics returned to baseline', 'nominal');
    }
  };

  // SOS Emergency Escalation Simulation Countdown
  function startEscalationCountdown(reason) {
    stopEscalationCountdown();
    const banner = document.getElementById('escalation-countdown-banner');
    const timerEl = document.getElementById('escalation-timer-sec');
    const stageEl = document.getElementById('escalation-stage-text');

    if (!banner || !timerEl) return;
    banner.classList.remove('hidden');

    let secondsLeft = 15;
    stageEl.textContent = `Alerting Contact 1 (Dr. Sarah Rostova) in ${secondsLeft}s unless cancelled`;

    countdownInterval = setInterval(() => {
      secondsLeft--;
      timerEl.textContent = secondsLeft;
      if (secondsLeft === 10) {
        stageEl.textContent = 'Auto-escalating to Contact 2 (Marcus Vance)...';
        window.logTimelineEvent('Escalation Chain: P1 → P2', 'Contact 1 timeout. Automated notification dispatched to Contact 2', 'warning');
      } else if (secondsLeft === 5) {
        stageEl.textContent = 'Auto-escalating to Emergency Services (112 Dispatch)...';
        window.logTimelineEvent('Escalation Chain: P2 → 112', 'Contact 2 timeout. Beacon dispatched to 112 Rescue Dispatch', 'critical');
      } else if (secondsLeft <= 0) {
        stopEscalationCountdown();
        stageEl.textContent = 'EMERGENCY BEACON DISPATCHED TO 112';
        window.logTimelineEvent('SOS Escalation Complete', 'All 3 Emergency contacts and municipal 112 notified with GPS location', 'critical');
      }
    }, 1000);
  }

  window.cancelEscalationCountdown = function () {
    stopEscalationCountdown();
    window.logTimelineEvent('Emergency Escalation Cancelled', 'Wearer cancelled automatic contact escalation sequence', 'info');
  };

  function stopEscalationCountdown() {
    if (countdownInterval) {
      clearInterval(countdownInterval);
      countdownInterval = null;
    }
    const banner = document.getElementById('escalation-countdown-banner');
    if (banner) banner.classList.add('hidden');
  }

  // Filter timeline
  window.filterTimeline = function (type, btn) {
    document.querySelectorAll('.timeline-chip').forEach(c => c.classList.remove('active'));
    if (btn) btn.classList.add('active');
    renderTimeline(type);
  };

  document.addEventListener('DOMContentLoaded', () => {
    renderTimeline('all');
  });
})();
