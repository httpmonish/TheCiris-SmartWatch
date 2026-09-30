/*
 ==============================================================================
 CIRIS WATCH — AI HARDWARE CHATBOT ENGINE v2
 Real-time telemetry context, markdown renderer, support ticket filing
 ==============================================================================
*/

(function() {
  'use strict';

  const drawer    = document.getElementById('ai-drawer');
  const messages  = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  let conversation = [];
  let isOpen = false;

  /* ------------------------------------------------------------------ */
  /* Drawer Toggle                                                        */
  /* ------------------------------------------------------------------ */
  window.toggleAiDrawer = function() {
    const d = document.getElementById('ai-drawer');
    const input = document.getElementById('chat-input');
    if (!d) return;
    isOpen = !d.classList.contains('open');
    d.classList.toggle('open', isOpen);
    if (isOpen) {
      setTimeout(() => {
        if (input) {
          input.focus();
          input.click();
        }
      }, 350);
    }
  };


  /* ------------------------------------------------------------------ */
  /* Simple Markdown → HTML                                               */
  /* ------------------------------------------------------------------ */
  function renderMarkdown(text) {
    return text
      .replace(/\*\*(.*?)\*\*/g, '<b>$1</b>')
      .replace(/`([^`]+)`/g,     '<code>$1</code>')
      .replace(/\n• /g,          '<br>• ')
      .replace(/\n\n/g,          '<br><br>')
      .replace(/\n/g,            '<br>');
  }

  /* ------------------------------------------------------------------ */
  /* Append Message Bubble                                                */
  /* ------------------------------------------------------------------ */
  function appendMessage(role, text, sensors, followUps) {
    const isBot = role === 'bot';

    const wrap = document.createElement('div');
    wrap.className = 'chat-msg ' + (isBot ? '' : 'chat-msg-user');

    const avatarIcon = isBot ? 'bot' : 'user';
    const avatarClass = isBot ? 'chat-avatar-bot' : 'chat-avatar-user';

    let innerHtml = `
      <div class="chat-avatar ${avatarClass}">
        <i data-lucide="${avatarIcon}"></i>
      </div>
      <div class="chat-bubble ${isBot ? 'chat-bubble-bot' : 'chat-bubble-user'}">
        <div>${renderMarkdown(text)}</div>
    `;

    if (isBot && sensors && sensors.length > 0) {
      innerHtml += `<div class="chat-sensors-row">`;
      sensors.forEach(s => {
        innerHtml += `<span class="chat-sensor-badge">${s}</span>`;
      });
      innerHtml += `</div>`;
    }

    if (isBot && followUps && followUps.length > 0) {
      innerHtml += `<div class="chat-followups">`;
      followUps.forEach(f => {
        const safe = f.replace(/'/g, "\\'").replace(/"/g, '&quot;');
        innerHtml += `<button class="chat-followup-btn" onclick="sendQuickPrompt('${safe}')">→ ${f}</button>`;
      });
      innerHtml += `</div>`;
    }

    innerHtml += `</div>`;
    wrap.innerHTML = innerHtml;
    messages.appendChild(wrap);
    messages.scrollTop = messages.scrollHeight;

    // Reinit lucide icons in new markup
    if (window.lucide) window.lucide.createIcons();
  }

  /* ------------------------------------------------------------------ */
  /* Typing Indicator                                                     */
  /* ------------------------------------------------------------------ */
  function showTyping() {
    const el = document.createElement('div');
    el.id = 'typing-el';
    el.className = 'typing-indicator';
    el.innerHTML = '<span class="typing-dot"></span> Decoding sensor matrix...';
    messages.appendChild(el);
    messages.scrollTop = messages.scrollHeight;
  }

  function hideTyping() {
    const el = document.getElementById('typing-el');
    if (el) el.remove();
  }

  /* ------------------------------------------------------------------ */
  /* Chat Submit                                                          */
  /* ------------------------------------------------------------------ */
  window.handleChatSubmit = function(e) {
    if (e) e.preventDefault();
    const query = (chatInput ? chatInput.value : '').trim();
    if (!query) return;

    appendMessage('user', query);
    conversation.push({ role: 'user', content: query });
    if (chatInput) chatInput.value = '';

    showTyping();

    fetch('/api/ai/chat', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ query, conversationHistory: conversation })
    })
      .then(r => r.json())
      .then(res => {
        hideTyping();
        if (res.reply) {
          appendMessage('bot', res.reply, res.relatedSensors, res.suggestedFollowUps);
          conversation.push({ role: 'assistant', content: res.reply });
        }
      })
      .catch(() => {
        hideTyping();
        appendMessage('bot', '⚠️ Connection error to ESP32-S3 diagnostic bridge. Please ensure the server is running on port 3000.');
      });
  };

  /* ------------------------------------------------------------------ */
  /* Quick Prompts                                                        */
  /* ------------------------------------------------------------------ */
  window.sendQuickPrompt = function(text) {
    if (chatInput) chatInput.value = text;
    if (!isOpen) window.toggleAiDrawer();
    setTimeout(() => window.handleChatSubmit(), 50);
  };

  /* ------------------------------------------------------------------ */
  /* Support / Complaint Ticket                                           */
  /* ------------------------------------------------------------------ */
  window.handleComplaintSubmit = function(e) {
    if (e) e.preventDefault();
    const payload = {
      name:     document.getElementById('ticket-name')?.value || '',
      email:    document.getElementById('ticket-email')?.value || '',
      category: document.getElementById('ticket-category')?.value || 'General',
      subject:  document.getElementById('ticket-subject')?.value || '',
      message:  document.getElementById('ticket-message')?.value || ''
    };

    fetch('/api/complaints', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(payload)
    })
      .then(r => r.json())
      .then(res => {
        if (res.success) {
          const t = res.ticket;
          closeComplaintModal();
          // Open AI drawer and show resolution
          if (!isOpen) window.toggleAiDrawer();
          appendMessage('bot',
            `**Support Ticket Logged** — \`${t.id}\`\n\n` +
            `**Priority**: ${t.priority}  **Status**: ${t.status}\n\n` +
            `**Automated AI Diagnostic**:\n${t.aiResolution}`,
            [],
            ['View live telemetry diagnostics', 'How does the solar charging work?']
          );
        }
      })
      .catch(() => {
        alert('Network error — please ensure server is running.');
      });
  };

  /* ------------------------------------------------------------------ */
  /* Init Welcome Message                                                 */
  /* ------------------------------------------------------------------ */
  function init() {
    appendMessage('bot',
      '**Welcome to Ciris Hardware Intelligence.** I am connected live to your ESP32-S3 smartwatch sensor telemetry.\n\n' +
      'You can ask me about live optical biosignals, solar charging efficiency, emergency SOS protocols, barometric flood risk, or file a technical support ticket.',
      [],
      [
        'What is my current heart rate and SpO2?',
        'How does the CN3065 solar charging work?',
        'Explain the panic button emergency protocol'
      ]
    );
  }

  init();
})();
