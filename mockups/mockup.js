/* Pinoy POS — shared mockup helpers */

function toggleTheme() {
  const html = document.documentElement;
  const current = html.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  html.setAttribute('data-theme', next);
  const label = document.getElementById('themeLabel');
  if (label) label.textContent = next === 'dark' ? 'Light mode' : 'Dark mode';
}

function showToast(message, type = 'info') {
  let toast = document.getElementById('toast');
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'toast';
    toast.className = 'toast';
    document.body.appendChild(toast);
  }
  const color = type === 'success' ? 'var(--success)' : type === 'error' ? 'var(--error)' : 'var(--info)';
  const icon = type === 'success' ? iconCheck() : type === 'error' ? iconWarn() : iconInfo();
  toast.innerHTML = icon + ' ' + escapeHtml(message);
  toast.querySelector('svg').style.fill = color;
  toast.classList.add('show');
  setTimeout(() => toast.classList.remove('show'), 2200);
}

function openDialog({ title, message, confirmLabel = 'OK', cancelLabel = 'Cancel', onConfirm, onCancel, destructive = false }) {
  let overlay = document.getElementById('overlay');
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.id = 'overlay';
    overlay.className = 'overlay';
    document.body.appendChild(overlay);
  }
  overlay.innerHTML = `
    <div class="dialog">
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(message)}</p>
      <div class="actions">
        <button class="btn btn-outlined" id="dlgCancel">${escapeHtml(cancelLabel)}</button>
        <button class="btn ${destructive ? 'btn-error' : 'btn-primary'}" id="dlgConfirm">${escapeHtml(confirmLabel)}</button>
      </div>
    </div>
  `;
  overlay.classList.add('show');

  overlay.querySelector('#dlgCancel').addEventListener('click', () => {
    overlay.classList.remove('show');
    if (onCancel) onCancel();
  });
  overlay.querySelector('#dlgConfirm').addEventListener('click', () => {
    overlay.classList.remove('show');
    if (onConfirm) onConfirm();
  });
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
}

/* Binds a keypad inside `scope` (CSS selector, default: whole document)
   so several mockup frames on one page stay independent. */
function setPinDigit(length, scope) {
  let value = '';
  const root = scope ? document.querySelector(scope) : document;
  if (!root) return;
  const dots = root.querySelectorAll('.pin-dot');
  const keys = root.querySelectorAll('.pin-key');
  keys.forEach(k => {
    k.addEventListener('click', () => {
      const d = k.dataset.d;
      if (d === 'back') {
        if (value.length > 0) value = value.slice(0, -1);
      } else if (d === 'ok') {
        // no-op in mockup
      } else if (value.length < length) {
        value += d;
      }
      if (value.length === length) {
        setTimeout(() => showToast('PIN entered', 'success'), 200);
      }
      updatePinDots(value, dots);
    });
  });
}

function updatePinDots(value, dots) {
  dots.forEach((dot, i) => dot.classList.toggle('filled', i < value.length));
}

function iconCheck() { return '<svg viewBox="0 0 24 24"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>'; }
function iconWarn() { return '<svg viewBox="0 0 24 24"><path d="M12 5.99 19.53 19H4.47L12 5.99M12 2 1 21h22L12 2zm1 14h-2v2h2v-2zm0-6h-2v4h2v-4z"/></svg>'; }
function iconInfo() { return '<svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>'; }

function suggest(btn) {
  const input = document.getElementById('aiInput');
  if (input && !input.disabled) {
    input.value = btn.textContent.trim();
    input.focus();
  }
}

function sendAi() {
  const input = document.getElementById('aiInput');
  if (!input || !input.value.trim() || input.disabled) return;
  const chat = document.getElementById('chatList');
  if (chat) {
    const q = input.value.trim();
    chat.insertAdjacentHTML('beforeend', `<div class="chat-row user"><div class="chat-bubble user">${escapeHtml(q)}</div></div>`);
    input.value = '';
    const typing = document.createElement('div');
    typing.className = 'chat-row';
    typing.id = 'aiTyping';
    typing.innerHTML = `<div class="icircle sm c-purple">✦</div><div style="display:flex;align-items:center;gap:4px;padding:10px 14px;background:var(--surface-elev);border-radius:18px;border-bottom-left-radius:4px;"><div class="typing-dot"></div><div class="typing-dot"></div><div class="typing-dot"></div></div>`;
    chat.appendChild(typing);
    chat.scrollTop = chat.scrollHeight;
    setTimeout(() => {
      const t = document.getElementById('aiTyping');
      if (t) t.remove();
      chat.insertAdjacentHTML('beforeend', `<div class="chat-row"><div class="icircle sm c-purple">✦</div><div class="chat-bubble ai">Here is a summary based on your data. In a live build this would come from the configured AI provider.</div></div>`);
      chat.scrollTop = chat.scrollHeight;
    }, 1200);
  }
}

function toggleRowSwitch(el) {
  const sw = el.querySelector('.toggle-switch');
  sw.classList.toggle('off');
}

function selectChip(el, group) {
  document.querySelectorAll(`[data-group="${group}"]`).forEach(c => c.classList.remove('on'));
  el.classList.add('on');
}

let openMenu = null;

function showMenu(event, items) {
  event.stopPropagation();
  closeMenu();

  const btn = event.currentTarget;
  const rect = btn.getBoundingClientRect();
  const menu = document.createElement('div');
  menu.className = 'menu';
  menu.innerHTML = items.map(item =>
    `<div class="menu-item ${item.cls || ''}" onclick="event.stopPropagation();${item.action};closeMenu()">${item.icon || ''}${escapeHtml(item.label)}</div>`
  ).join('');
  document.body.appendChild(menu);

  const backdrop = document.createElement('div');
  backdrop.className = 'menu-backdrop';
  backdrop.onclick = closeMenu;
  document.body.appendChild(backdrop);
  openMenu = menu;

  // Position under the button, flip up if it would overflow.
  menu.style.left = rect.left + 'px';
  menu.style.top = (rect.bottom + 6) + 'px';
  const m = menu.getBoundingClientRect();
  if (m.bottom > window.innerHeight) menu.style.top = (rect.top - m.height - 6) + 'px';
  if (m.right > window.innerWidth) { menu.style.left = 'auto'; menu.style.right = (window.innerWidth - rect.right) + 'px'; }
}

function closeMenu() {
  if (openMenu) { openMenu.remove(); openMenu = null; }
  document.querySelectorAll('.menu-backdrop').forEach(b => b.remove());
}

/* Renders a pagination bar: "1–10 of N" + ‹ 1 2 3 › buttons.
   goFn is the name of the caller's page-change function (e.g. 'goPage').
   cls adds extra classes (e.g. 'standalone' when the bar is not inside a card). */
function pagerHtml(total, page, pageSize, goFn, cls) {
  const totalPages = Math.ceil(total / pageSize);
  if (totalPages <= 1) return '';
  const start = (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, total);
  let nums = '';
  for (let i = 1; i <= totalPages; i++) {
    nums += `<button class="pg-btn ${i === page ? 'on' : ''}" onclick="${goFn}(${i})">${i}</button>`;
  }
  return `<div class="pager ${cls || ''}">
    <span class="pager-info">${start}–${end} of ${total}</span>
    <div class="pager-btns">
      <button class="pg-btn" ${page === 1 ? 'disabled' : ''} onclick="${goFn}(${page - 1})" aria-label="Previous page"><svg viewBox="0 0 24 24"><path d="M15.41 7.41 14 6l-6 6 6 6 1.41-1.41L10.83 12z"/></svg></button>
      ${nums}
      <button class="pg-btn" ${page === totalPages ? 'disabled' : ''} onclick="${goFn}(${page + 1})" aria-label="Next page"><svg viewBox="0 0 24 24"><path d="M10 6 8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg></button>
    </div>
  </div>`;
}
