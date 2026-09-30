/* ==============================================================================
   CIRIS COMMAND PALETTE (Ctrl / Cmd + K)
   Fast keyboard-first navigation and actions
   ============================================================================== */

(function () {
  'use strict';

  const COMMANDS = [
    { title: 'Jump to Live Telemetry Dashboard', category: 'Navigation', icon: 'activity', action: () => location.hash = '#dashboard' },
    { title: 'Jump to Multi-Dataset ML Platform', category: 'Navigation', icon: 'layers', action: () => location.hash = '#ml-datasets-section' },
    { title: 'Jump to Hardware Architecture (BOM)', category: 'Navigation', icon: 'cpu', action: () => location.hash = '#specs' },
    { title: 'Open Simulation Lab', category: 'Testing', icon: 'flask-conical', action: () => window.toggleSimulationLab && window.toggleSimulationLab() },
    { title: 'Trigger Freefall & Impact Scenario', category: 'Testing', icon: 'shield-alert', action: () => window.runSimulationScenario && window.runSimulationScenario('freefall') },
    { title: 'Trigger Flash Flood & Storm Scenario', category: 'Testing', icon: 'cloud-rain', action: () => window.runSimulationScenario && window.runSimulationScenario('storm') },
    { title: 'Reset to Baseline Nominal State', category: 'Testing', icon: 'check-circle-2', action: () => window.runSimulationScenario && window.runSimulationScenario('nominal') },
    { title: 'Toggle Theme (Dark / Clinical White)', category: 'Preferences', icon: 'sun', action: () => window.toggleTheme && window.toggleTheme() },
    { title: 'Open Settings Drawer', category: 'Preferences', icon: 'settings', action: () => window.toggleSettingsDrawer && window.toggleSettingsDrawer() },
    { title: 'Open CIRIS Assistant', category: 'AI Intelligence', icon: 'sparkles', action: () => window.toggleAiDrawer && window.toggleAiDrawer() },
    { title: 'Export Live Telemetry as CSV', category: 'Data', icon: 'file-text', action: () => window.exportTelemetry && window.exportTelemetry('csv') },
    { title: 'Export Live Telemetry as JSON', category: 'Data', icon: 'file-code', action: () => window.exportTelemetry && window.exportTelemetry('json') },
    { title: 'File Technical Support / RMA Ticket', category: 'Support', icon: 'life-buoy', action: () => window.openComplaintModal && window.openComplaintModal() }
  ];

  window.toggleCommandPalette = function () {
    const modal = document.getElementById('command-palette-modal');
    const input = document.getElementById('command-palette-input');
    if (!modal) return;
    const isHidden = modal.classList.contains('hidden');
    modal.classList.toggle('hidden', !isHidden);
    if (isHidden && input) {
      input.value = '';
      renderCommands(COMMANDS);
      setTimeout(() => input.focus(), 50);
    }
  };

  function renderCommands(list) {
    const listEl = document.getElementById('command-palette-list');
    if (!listEl) return;

    if (list.length === 0) {
      listEl.innerHTML = '<div class="palette-empty">No matching commands found.</div>';
      return;
    }

    listEl.innerHTML = list.map((cmd, idx) => `
      <div class="palette-item" onclick="executePaletteCommand(${idx})" tabindex="0">
        <div class="palette-item-icon"><i data-lucide="${cmd.icon}"></i></div>
        <div class="palette-item-info">
          <div class="palette-item-title">${cmd.title}</div>
          <div class="palette-item-cat">${cmd.category}</div>
        </div>
        <div class="palette-item-shortcut">↵</div>
      </div>
    `).join('');

    if (window.lucide) window.lucide.createIcons();
  }

  window.filterPaletteCommands = function () {
    const input = document.getElementById('command-palette-input');
    const q = (input?.value || '').toLowerCase().trim();
    const filtered = COMMANDS.filter(c => c.title.toLowerCase().includes(q) || c.category.toLowerCase().includes(q));
    renderCommands(filtered);
  };

  window.executePaletteCommand = function (index) {
    const input = document.getElementById('command-palette-input');
    const q = (input?.value || '').toLowerCase().trim();
    const currentList = q ? COMMANDS.filter(c => c.title.toLowerCase().includes(q) || c.category.toLowerCase().includes(q)) : COMMANDS;
    if (currentList[index]) {
      window.toggleCommandPalette();
      currentList[index].action();
    }
  };

  // Global Keyboard Listener for Cmd/Ctrl+K
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      window.toggleCommandPalette();
    } else if (e.key === 'Escape') {
      const modal = document.getElementById('command-palette-modal');
      if (modal && !modal.classList.contains('hidden')) {
        modal.classList.add('hidden');
      }
    }
  });
})();
