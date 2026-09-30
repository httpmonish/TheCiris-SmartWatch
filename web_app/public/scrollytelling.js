/*
 ============================================================================
 CIRIS WATCH — 300-FRAME SCROLLYTELLING ENGINE v3
 Professional scroll-driven canvas with smooth lerp, SVG HUD, chapter logic
 ============================================================================
*/

(function () {
  'use strict';

  const TOTAL_FRAMES = 300;
  const LERP         = 0.10;  // Smooth inertia factor

  const canvas    = document.getElementById('scrolly-canvas');
  const ctx       = canvas.getContext('2d', { alpha: false });
  const hudSvg    = document.getElementById('hud-svg');
  const loaderEl  = document.getElementById('canvas-loader');
  const loaderBar = document.getElementById('loader-progress');
  const loaderPct = document.getElementById('loader-pct');
  const hudPct    = document.getElementById('scroll-hud-pct');
  const hudFill   = document.getElementById('scroll-hud-fill');
  const hudStage  = document.getElementById('scroll-hud-stage');
  const navbar    = document.getElementById('navbar');

  let images      = new Array(TOTAL_FRAMES);
  let loaded      = 0;
  let targetProg  = 0;
  let currentProg = 0;
  let showHud     = true;
  let allLoaded   = false;

  /* ---------------------------------------------------------------------- */
  /* Hardware component HUD annotations (only the 16 real BOM components)   */
  /* ---------------------------------------------------------------------- */
  const annotations = [
    {
      id: 'oled',
      label: '0.96" OLED SSD1306',
      sub: 'I2C Display (0x3C)',
      show: [0.16, 0.44],
      ax: 0.50, ay: 0.28,
      side: 'left'
    },
    {
      id: 'esp32',
      label: 'ESP32-S3 MCU',
      sub: 'Dual-Core Xtensa LX7 · BLE 5.0',
      show: [0.20, 0.70],
      ax: 0.52, ay: 0.50,
      side: 'right'
    },
    {
      id: 'max30101',
      label: 'MAX30101',
      sub: 'Optical PPG & SpO2 (0x57)',
      show: [0.34, 0.64],
      ax: 0.57, ay: 0.78,
      side: 'right'
    },
    {
      id: 'bmi270',
      label: 'BMI270 IMU',
      sub: '6-Axis Motion · Fall Detection',
      show: [0.36, 0.64],
      ax: 0.43, ay: 0.53,
      side: 'left'
    },
    {
      id: 'thermal',
      label: 'MAX30208 / SHT31',
      sub: 'Clinical Skin Temp ±0.1°C',
      show: [0.40, 0.64],
      ax: 0.55, ay: 0.73,
      side: 'right'
    },
    {
      id: 'panic',
      label: 'Tactile Panic Button',
      sub: 'Waterproof SOS (GPIO 3)',
      show: [0.60, 0.77],
      ax: 0.66, ay: 0.38,
      side: 'right'
    },
    {
      id: 'haptic',
      label: 'ERM Motor + Piezo',
      sub: 'Haptic & Audible 95dB Alert',
      show: [0.61, 0.77],
      ax: 0.35, ay: 0.57,
      side: 'left'
    },
    {
      id: 'cn3065',
      label: 'CN3065 Solar IC',
      sub: 'CC/CV MPPT Charger (GPIO 4)',
      show: [0.74, 0.90],
      ax: 0.55, ay: 0.46,
      side: 'right'
    },
    {
      id: 'solar',
      label: 'Flexible Solar Panel',
      sub: 'Strap-integrated PV harvester',
      show: [0.74, 0.90],
      ax: 0.33, ay: 0.71,
      side: 'left'
    },
    {
      id: 'lipo',
      label: 'LiPo Battery Cell',
      sub: '3.7V · ADC monitor GPIO 0',
      show: [0.22, 0.87],
      ax: 0.50, ay: 0.65,
      side: 'left'
    }
  ];

  /* ---------------------------------------------------------------------- */
  /* Scroll-synchronized chapter overlay engine                              */
  /* ---------------------------------------------------------------------- */
  function updateChapters(progress) {
    chapters.forEach(ch => {
      const el = document.getElementById(ch.id);
      if (!el) return;
      const inner = el.querySelector('.ch-center, .ch-left, .ch-right');
      if (!inner) return;

      let op = 0;
      let ty = 20;

      if (ch.id === 'ch-hero') {
        if (progress <= 0.08) {
          op = 1;
          ty = 0;
        } else if (progress <= ch.end) {
          const f = (ch.end - progress) / (ch.end - 0.08);
          op = Math.max(0, Math.min(1, f));
          ty = (1 - f) * -18;
        } else {
          op = 0;
          ty = -18;
        }
      } else if (ch.id === 'ch-final') {
        const fade = ch.fade || 0.03;
        if (progress < ch.start) {
          op = 0;
          ty = 20;
        } else if (progress < ch.start + fade) {
          const f = (progress - ch.start) / fade;
          op = Math.max(0, Math.min(1, f));
          ty = (1 - f) * 20;
        } else {
          op = 1;
          ty = 0;
        }
      } else {
        const fade = ch.fade || 0.03;
        if (progress >= ch.start && progress <= ch.end) {
          if (progress < ch.start + fade) {
            const f = (progress - ch.start) / fade;
            op = Math.max(0, Math.min(1, f));
            ty = (1 - f) * 20;
          } else if (progress > ch.end - fade) {
            const f = (ch.end - progress) / fade;
            op = Math.max(0, Math.min(1, f));
            ty = (1 - f) * -16;
          } else {
            op = 1;
            ty = 0;
          }
        } else if (progress < ch.start) {
          ty = 20;
          op = 0;
        } else {
          ty = -16;
          op = 0;
        }
      }

      if (op > 0.005) {
        el.style.display = 'flex';
        el.style.opacity = op.toFixed(3);
        inner.style.transform = `translate3d(0, ${ty.toFixed(1)}px, 0)`;
        inner.style.pointerEvents = op > 0.4 ? 'auto' : 'none';
      } else {
        el.style.display = 'none';
        el.style.opacity = '0';
        inner.style.pointerEvents = 'none';
      }
    });
  }

  /* Chapter zones (synchronized with 300 JPG frames) */
  const chapters = [
    { id: 'ch-hero',         start: 0.00, end: 0.12, fade: 0.030 },
    { id: 'ch-architecture', start: 0.13, end: 0.38, fade: 0.035 },
    { id: 'ch-sensors',      start: 0.39, end: 0.58, fade: 0.035 },
    { id: 'ch-safety',       start: 0.59, end: 0.73, fade: 0.030 },
    { id: 'ch-solar',        start: 0.74, end: 0.86, fade: 0.030 },
    { id: 'ch-final',        start: 0.87, end: 1.00, fade: 0.030 }
  ];

  const stages = [
    { start: 0.00, label: 'Assembled' },
    { start: 0.14, label: 'Core disassembly' },
    { start: 0.40, label: 'Biosensing matrix' },
    { start: 0.60, label: 'ESP32-S3 & safety' },
    { start: 0.75, label: 'Solar energy chain' },
    { start: 0.88, label: 'Waterproof sealing' },
    { start: 0.96, label: 'Final reassembly' }
  ];

  /* ---------------------------------------------------------------------- */
  /* Canvas sizing (DPR-aware)                                               */
  /* ---------------------------------------------------------------------- */
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = window.innerWidth;
    const h = window.innerHeight;
    canvas.width  = w * dpr;
    canvas.height = h * dpr;
    canvas.style.width  = w + 'px';
    canvas.style.height = h + 'px';
    ctx.scale(dpr, dpr);
  }

  /* ---------------------------------------------------------------------- */
  /* Image preloading                                                        */
  /* ---------------------------------------------------------------------- */
  function dismissLoader() {
    if (loaderEl && loaderEl.style.display !== 'none') {
      loaderEl.style.opacity = '0';
      loaderEl.style.pointerEvents = 'none';
      setTimeout(() => {
        if (loaderEl) loaderEl.style.display = 'none';
      }, 600);
    }
  }

  function preload() {
    // Safety timer: guarantee loader dismissal after 2.5s maximum
    setTimeout(dismissLoader, 2500);

    for (let i = 1; i <= TOTAL_FRAMES; i++) {
      const img = new Image();
      img.decoding = 'async';
      img.src = 'frames/ezgif-frame-' + String(i).padStart(3, '0') + '.jpg';

      img.onload = function () {
        loaded++;
        const pct = Math.round((loaded / TOTAL_FRAMES) * 100);
        if (loaderBar)  loaderBar.style.width = pct + '%';
        if (loaderPct)  loaderPct.textContent = pct + '%';
        if (loaded === 1) draw(0);

        if (loaded >= 25 && !allLoaded) {
          dismissLoader();
        }

        if (loaded >= TOTAL_FRAMES) {
          allLoaded = true;
          dismissLoader();
        }
      };

      img.onerror = function () {
        loaded++;
        if (loaded >= 15) {
          dismissLoader();
        }
      };

      images[i - 1] = img;
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Draw frame                                                              */
  /* ---------------------------------------------------------------------- */
  function draw(progress) {
    const w = window.innerWidth;
    const h = window.innerHeight;

    ctx.fillStyle = '#050505';
    ctx.fillRect(0, 0, w, h);

    const idx = Math.min(TOTAL_FRAMES - 1, Math.max(0, Math.round(progress * (TOTAL_FRAMES - 1))));
    const img = images[idx];

    if (img && img.complete && img.naturalWidth > 0) {
      const imgAR = img.naturalWidth / img.naturalHeight;
      const vpAR  = w / h;
      let dw, dh;

      if (vpAR > imgAR) {
        dh = h * 0.90;
        dw = dh * imgAR;
      } else {
        dw = w * 0.90;
        dh = dw / imgAR;
      }

      const dx = (w - dw) / 2;
      const dy = (h - dh) / 2;
      ctx.drawImage(img, dx, dy, dw, dh);
    }

    // Render CIRIS brand logo in capital letters at start of animation (progress 0.0 to 0.08)
    if (progress <= 0.08) {
      const alpha = Math.max(0, 1 - (progress / 0.08));
      ctx.save();
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.font = '900 clamp(48px, 12vw, 120px) Inter, sans-serif';
      ctx.fillStyle = `rgba(255, 255, 255, ${0.12 * alpha})`;
      ctx.letterSpacing = '0.35em';
      ctx.fillText('CIRIS', w / 2, h * 0.48);
      ctx.restore();
    }

    drawHUD(progress, w, h);
    updateUI(progress);
  }


  /* ---------------------------------------------------------------------- */
  /* SVG HUD laser callout overlay                                           */
  /* ---------------------------------------------------------------------- */
  function drawHUD(progress, w, h) {
    if (!showHud || !hudSvg) {
      if (hudSvg) hudSvg.innerHTML = '';
      return;
    }

    const LW = 168;
    const LH = 42;
    const OFF = 78;
    let parts = [];

    annotations.forEach(item => {
      if (progress < item.show[0] || progress > item.show[1]) return;

      const fi  = Math.min(1, (progress - item.show[0]) / 0.035);
      const fo  = Math.min(1, (item.show[1] - progress) / 0.035);
      const op  = Math.min(fi, fo);
      if (op < 0.01) return;

      const ax = item.ax * w;
      const ay = item.ay * h;

      let lx, ly, ex, ey;
      if (item.side === 'right') {
        lx = ax + OFF;
        ex = ax + OFF * 0.50;
      } else {
        lx = ax - OFF - LW;
        ex = ax - OFF * 0.50;
      }
      ly = ay - LH / 2;
      ey = ay;

      const path = item.side === 'right'
        ? `M ${ax} ${ay} L ${ex} ${ey} L ${lx} ${ly + LH / 2}`
        : `M ${ax} ${ay} L ${ex} ${ey} L ${lx + LW} ${ly + LH / 2}`;

      parts.push(`
        <g opacity="${op.toFixed(3)}">
          <circle cx="${ax}" cy="${ay}" r="3.5" fill="#06B6D4" filter="url(#glow)"/>
          <circle cx="${ax}" cy="${ay}" r="8"   fill="none" stroke="#06B6D4" stroke-width="1" opacity="0.3"/>
          <path d="${path}" fill="none" stroke="#06B6D4" stroke-width="1.1"
                stroke-dasharray="4 3" style="animation:dash 16s linear infinite;"/>
          <rect x="${lx}" y="${ly}" width="${LW}" height="${LH}"
                rx="7" fill="rgba(5,5,5,0.9)" stroke="rgba(6,182,212,0.4)" stroke-width="1"/>
          <text x="${lx + 10}" y="${ly + 14}" font-family="JetBrains Mono,monospace"
                font-size="10.5" font-weight="700" fill="rgba(255,255,255,0.95)">${item.label}</text>
          <text x="${lx + 10}" y="${ly + 28}" font-family="JetBrains Mono,monospace"
                font-size="9" fill="rgba(255,255,255,0.45)">${item.sub}</text>
        </g>
      `);
    });

    hudSvg.innerHTML = `
      <defs>
        <filter id="glow" x="-60%" y="-60%" width="220%" height="220%">
          <feGaussianBlur stdDeviation="2.5" result="blur"/>
          <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
        </filter>
        <style>@keyframes dash { to { stroke-dashoffset: -80; } }</style>
      </defs>
      ${parts.join('')}
    `;
  }

  /* ---------------------------------------------------------------------- */
  /* UI state updates                                                        */
  /* ---------------------------------------------------------------------- */
  function updateUI(progress) {
    const pct = Math.round(progress * 100);
    if (hudPct)  hudPct.textContent = pct + '%';
    if (hudFill) hudFill.style.width = pct + '%';

    let stage = stages[0].label;
    for (let i = stages.length - 1; i >= 0; i--) {
      if (progress >= stages[i].start) { stage = stages[i].label; break; }
    }
    if (hudStage) hudStage.textContent = stage;

    updateChapters(progress);

    if (navbar) {
      navbar.classList.add('visible');
      navbar.classList.toggle('scrolled', window.scrollY > 40);
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Scroll-synchronized chapter overlay engine                              */
  /* ---------------------------------------------------------------------- */
  function updateChapters(progress) {
    chapters.forEach(ch => {
      const el = document.getElementById(ch.id);
      if (!el) return;
      const inner = el.querySelector('.ch-center, .ch-left, .ch-right');
      if (!inner) return;

      let op = 0;
      let ty = 20;

      if (ch.id === 'ch-hero') {
        if (progress <= 0.08) {
          op = 1;
          ty = 0;
        } else if (progress <= ch.end) {
          const f = (ch.end - progress) / (ch.end - 0.08);
          op = Math.max(0, Math.min(1, f));
          ty = (1 - f) * -18;
        } else {
          op = 0;
          ty = -18;
        }
      } else if (ch.id === 'ch-final') {
        const fade = ch.fade || 0.03;
        if (progress < ch.start) {
          op = 0;
          ty = 20;
        } else if (progress < ch.start + fade) {
          const f = (progress - ch.start) / fade;
          op = Math.max(0, Math.min(1, f));
          ty = (1 - f) * 20;
        } else {
          op = 1;
          ty = 0;
        }
      } else {
        const fade = ch.fade || 0.03;
        if (progress >= ch.start && progress <= ch.end) {
          if (progress < ch.start + fade) {
            const f = (progress - ch.start) / fade;
            op = Math.max(0, Math.min(1, f));
            ty = (1 - f) * 20;
          } else if (progress > ch.end - fade) {
            const f = (ch.end - progress) / fade;
            op = Math.max(0, Math.min(1, f));
            ty = (1 - f) * -16;
          } else {
            op = 1;
            ty = 0;
          }
        } else if (progress < ch.start) {
          ty = 20;
          op = 0;
        } else {
          ty = -16;
          op = 0;
        }
      }

      if (op > 0.005) {
        el.style.display = 'flex';
        el.style.opacity = op.toFixed(3);
        inner.style.transform = `translate3d(0, ${ty.toFixed(1)}px, 0)`;
        inner.style.pointerEvents = op > 0.4 ? 'auto' : 'none';
      } else {
        el.style.display = 'none';
        el.style.opacity = '0';
        inner.style.pointerEvents = 'none';
      }
    });
  }

  /* ---------------------------------------------------------------------- */
  /* Scroll → progress                                                       */
  /* ---------------------------------------------------------------------- */
  function onScroll() {
    const container = document.getElementById('scrolly');
    if (!container) return;
    const track = container.offsetHeight - window.innerHeight;
    if (track <= 0) return;
    targetProg = Math.max(0, Math.min(1, window.scrollY / track));
  }

  /* ---------------------------------------------------------------------- */
  /* rAF animation loop                                                      */
  /* ---------------------------------------------------------------------- */
  function loop() {
    const delta = targetProg - currentProg;
    if (Math.abs(delta) > 0.0001) {
      currentProg += delta * LERP;
      draw(currentProg);
    }
    requestAnimationFrame(loop);
  }

  /* ---------------------------------------------------------------------- */
  /* Public API                                                              */
  /* ---------------------------------------------------------------------- */
  window.toggleHudLabels = function () {
    showHud = !showHud;
    const btn = document.getElementById('toggle-labels-btn');
    if (btn) btn.style.borderColor = showHud ? '#06B6D4' : 'rgba(255,255,255,0.13)';
    draw(currentProg);
  };

  /* ---------------------------------------------------------------------- */
  /* Init                                                                    */
  /* ---------------------------------------------------------------------- */
  resize();
  draw(0);
  preload();

  if (navbar) navbar.classList.add('visible');

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', () => { resize(); draw(currentProg); });

  loop();

})();
