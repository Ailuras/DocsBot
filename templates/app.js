const API_BASE = (() => {
  const path = location.pathname;
  if (path.endsWith('/')) return '.';
  const lastSlash = path.lastIndexOf('/');
  return lastSlash >= 0 ? path.slice(0, lastSlash) : '';
})();

// ── Theme ─────────────────────────────────────────────
function initTheme() {
  const saved = localStorage.getItem('docsbot:theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
  const btn = document.getElementById('themeToggle');
  if (btn) btn.title = saved === 'dark' ? '切换到亮色模式' : '切换到暗色模式';
}

function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('docsbot:theme', next);
  const btn = document.getElementById('themeToggle');
  if (btn) btn.title = next === 'dark' ? '切换到亮色模式' : '切换到暗色模式';
}

// ── Utilities ─────────────────────────────────────────
function esc(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function inline(s) {
  if (!s) return '';
  return String(s)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`\n]+)`/g, '<code>$1</code>');
}

function badgeClass(status) {
  const map = {
    'open': 'badge-open',
    'in-progress': 'badge-in-progress',
    'blocked': 'badge-blocked',
    'done': 'badge-done',
    'abandoned': 'badge-abandoned',
  };
  return map[status] || 'badge-open';
}

function bucketLineVar(bucket) {
  const p = (bucket || '').toLowerCase().replace(/^p/, '');
  const n = parseInt(p, 10);
  if (n >= 0 && n <= 5) return `var(--p${n}-line)`;
  return 'var(--border-default)';
}

function bucketBgVar(bucket) {
  const p = (bucket || '').toLowerCase().replace(/^p/, '');
  const n = parseInt(p, 10);
  if (n >= 0 && n <= 5) return `var(--p${n}-bg)`;
  return 'transparent';
}

function bucketColorVar(bucket) {
  const p = (bucket || '').toLowerCase().replace(/^p/, '');
  const n = parseInt(p, 10);
  if (n >= 0 && n <= 5) return `var(--p${n})`;
  return 'var(--text-muted)';
}

// ── API ───────────────────────────────────────────────
function apiXhr(path) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', API_BASE + path, true);
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        try { resolve(JSON.parse(xhr.responseText)); }
        catch (e) { reject(new Error('JSON parse error')); }
      } else {
        reject(new Error(`HTTP ${xhr.status}`));
      }
    };
    xhr.onerror = () => reject(new Error('Network error'));
    xhr.ontimeout = () => reject(new Error('Timeout'));
    xhr.send();
  });
}

async function loadProjects() {
  const data = await apiXhr('/api/projects');
  return data.projects || [];
}

async function loadProjectData(projectId) {
  const files = ['meta.js', 'research.js', 'backlog.js', 'roadmap.js', 'changelog.js', 'notes.js'];
  const raw = {};
  for (const f of files) {
    try {
      const res = await apiXhr(`/api/projects/${encodeURIComponent(projectId)}/data/${f}`);
      raw[f] = res.content || '';
    } catch (e) { raw[f] = ''; }
  }
  const sandbox = { window: {} };
  for (const [fname, content] of Object.entries(raw)) {
    if (!content) continue;
    try { new Function('window', content)(sandbox.window); }
    catch (e) { console.warn('Parse error in', fname, e); }
  }
  return {
    meta: sandbox.window.AUGUR_META || {},
    research: sandbox.window.AUGUR_RESEARCH || [],
    backlog: sandbox.window.AUGUR_BACKLOG || [],
    buckets: sandbox.window.AUGUR_BACKLOG_BUCKETS || [],
    roadmap: sandbox.window.AUGUR_ROADMAP || null,
    changelog: sandbox.window.AUGUR_CHANGELOG || [],
    notes: sandbox.window.AUGUR_NOTES || [],
  };
}

// ── Render: Recent Tasks ──────────────────────────────
function renderTodo(data) {
  const tasks = (data.backlog || []).filter(t => t.status !== 'done').sort((a, b) => {
    const pa = a.bucket || '';
    const pb = b.bucket || '';
    if (pa !== pb) return pa.localeCompare(pb);
    const order = { 'in-progress': 0, 'blocked': 1, 'open': 2 };
    return (order[a.status] || 99) - (order[b.status] || 99);
  });

  document.getElementById('todoCount').textContent = `${tasks.length} items`;

  if (!tasks.length) {
    document.getElementById('todoBody').innerHTML = '<div class="empty-state">All tasks completed</div>';
    return;
  }

  document.getElementById('todoBody').innerHTML = `
    <div class="card-list">
      ${tasks.map(t => `
        <div class="row-card" data-todo-id="${esc(t.id)}" style="--bucket-line: ${bucketLineVar(t.bucket)};">
          <div class="row-card-main">
            <div class="row-card-title">${esc(t.title)}</div>
            <div class="row-card-meta">
              <span style="font-family:var(--font-mono);color:var(--text-muted);">${esc(t.id)}</span>
              <span class="sep">·</span>
              <span>${esc(t.module || '-')}</span>
              ${t.size ? `<span class="sep">·</span><span>size: ${esc(t.size)}</span>` : ''}
              ${t.effort ? `<span class="sep">·</span><span>effort: ${esc(t.effort)}</span>` : ''}
            </div>
          </div>
          <div class="row-card-actions">
            <span class="badge ${badgeClass(t.status)}">${esc(t.status)}</span>
            <span class="badge badge-bucket">${esc(t.bucket || '-')}</span>
          </div>
        </div>
      `).join('')}
    </div>
  `;

  // Bind click handlers
  document.querySelectorAll('#todoBody .row-card').forEach(card => {
    card.addEventListener('click', () => {
      const id = card.dataset.todoId;
      const task = tasks.find(t => t.id === id);
      if (task) openTodoModal(task);
    });
  });
}

// ── Render: Research ──────────────────────────────────
function renderResearch(data) {
  const items = data.research || [];
  document.getElementById('researchCount').textContent = `${items.length} items`;

  if (!items.length) {
    document.getElementById('researchBody').innerHTML = '<div class="empty-state">No research directions yet</div>';
    return;
  }

  // Sort: in-progress first, then by status
  const sorted = [...items].sort((a, b) => {
    const order = { 'in-progress': 0, 'blocked': 1, 'open': 2, 'done': 3, 'abandoned': 4 };
    return (order[a.status] || 99) - (order[b.status] || 99);
  });

  document.getElementById('researchBody').innerHTML = `
    <div class="card-grid">
      ${sorted.map(r => `
        <div class="grid-card" data-research-id="${esc(r.id)}" style="--card-accent: ${r.status === 'in-progress' ? 'var(--accent)' : 'var(--border-default)'};">
          <div class="grid-card-header">
            <span class="grid-card-id">${esc(r.id)}</span>
            <div class="grid-card-badges">
              <span class="badge ${badgeClass(r.status)}">${esc(r.status)}</span>
              ${r.kind ? `<span class="badge badge-kind">${esc(r.kind)}</span>` : ''}
            </div>
          </div>
          ${r.codename ? `<div class="grid-card-subtitle">${esc(r.codename)}</div>` : ''}
          <div class="grid-card-title">${esc(r.title)}</div>
          ${r.hypothesis ? `<div class="grid-card-summary">${inline(r.hypothesis)}</div>` : ''}
        </div>
      `).join('')}
    </div>
  `;

  document.querySelectorAll('#researchBody .grid-card').forEach(card => {
    card.addEventListener('click', () => {
      const id = card.dataset.researchId;
      const item = sorted.find(r => r.id === id);
      if (item) openResearchModal(item);
    });
  });
}

// ── Render: Engineering ───────────────────────────────
function renderEngineering(data) {
  const tasks = data.backlog || [];

  // Discover all modules present in data
  const moduleOrder = ['modeling', 'instantiation', 'smt', 'llm', 'infra'];
  const seenModules = [...new Set(tasks.map(t => t.module || 'infra'))];
  // Sort: known order first, then alphabetical for unknown
  const orderedModules = [
    ...moduleOrder.filter(m => seenModules.includes(m)),
    ...seenModules.filter(m => !moduleOrder.includes(m)).sort(),
  ];
  const groups = {};
  for (const mod of orderedModules) groups[mod] = [];
  for (const t of tasks) {
    const mod = t.module || 'infra';
    if (!groups[mod]) groups[mod] = [];
    groups[mod].push(t);
  }

  // Labels: fallback to capitalized module name
  const labelMap = {
    smt: 'SMT Core', llm: 'LLM Loop', infra: 'Infrastructure',
    modeling: 'Modeling', instantiation: 'Instantiation',
  };
  const icons = { smt: '⚙️', llm: '🔄', infra: '🏗️', modeling: '📐', instantiation: '🔩' };

  const total = tasks.length;
  document.getElementById('engineeringCount').textContent = `${total} items`;

  if (!total) {
    document.getElementById('engineeringBody').innerHTML = '<div class="empty-state">No engineering tasks yet</div>';
    return;
  }

  document.getElementById('engineeringBody').innerHTML = Object.entries(groups).map(([mod, items]) => {
    if (!items.length) return '';
    const label = labelMap[mod] || (mod.charAt(0).toUpperCase() + mod.slice(1));
    return `
      <div class="module-group">
        <div class="module-group-header">
          <div class="module-group-icon">${icons[mod] || '🔧'}</div>
          <span class="module-group-title">${esc(label)}</span>
          <span class="module-group-count">${items.length}</span>
        </div>
        <div class="module-group-grid">
          ${items.map(t => `
            <div class="compact-card" data-eng-id="${esc(t.id)}" style="--bucket-line: ${bucketLineVar(t.bucket)};">
              <div class="compact-card-title">${esc(t.title)}</div>
              <div class="compact-card-meta">
                <span class="badge ${badgeClass(t.status)}">${esc(t.status)}</span>
                <span class="badge badge-bucket">${esc(t.bucket || '-')}</span>
                ${t.size ? `<span style="font-size:0.72rem;color:var(--text-muted);font-family:var(--font-mono);">${esc(t.size)}</span>` : ''}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }).join('');

  document.querySelectorAll('#engineeringBody .compact-card').forEach(card => {
    card.addEventListener('click', () => {
      const id = card.dataset.engId;
      const task = tasks.find(t => t.id === id);
      if (task) openTodoModal(task);
    });
  });
}

// ── Render: Notes ─────────────────────────────────────
function renderNotes(data) {
  const notes = (data.notes || []).sort((a, b) => (b.date || '').localeCompare(a.date || ''));
  document.getElementById('notesCount').textContent = `${notes.length} notes`;

  if (!notes.length) {
    document.getElementById('notesBody').innerHTML = '<div class="empty-state">No notes yet</div>';
    return;
  }

  document.getElementById('notesBody').innerHTML = `
    <div class="card-grid">
      ${notes.map(n => `
        <div class="note-card" data-note-path="${esc(n.path)}">
          <div class="note-card-date">${esc(n.date)}</div>
          <div class="note-card-title">${esc(n.title)}</div>
          ${n.excerpt ? `<div class="note-card-excerpt">${esc(n.excerpt)}</div>` : ''}
          ${(n.tags && n.tags.length) ? `<div class="note-tags">${n.tags.map(t => `<span class="note-tag">${esc(t)}</span>`).join('')}</div>` : ''}
        </div>
      `).join('')}
    </div>
  `;

  document.querySelectorAll('#notesBody .note-card').forEach(card => {
    card.addEventListener('click', () => {
      const path = card.dataset.notePath;
      if (path) openNoteModal(path);
    });
  });
}

// ── Render all ────────────────────────────────────────
function renderAll(data) {
  renderTodo(data);
  renderResearch(data);
  renderEngineering(data);
  renderNotes(data);
}

// ═══════════════════════════════════════════════════════
//  MODALS — each module has its own content template
// ═══════════════════════════════════════════════════════

function showModal(htmlContent) {
  const overlay = document.getElementById('modalOverlay');
  const body = document.getElementById('modalBody');
  body.innerHTML = htmlContent;
  overlay.classList.add('active');
  document.body.style.overflow = 'hidden';
}

function hideModal() {
  const overlay = document.getElementById('modalOverlay');
  overlay.classList.remove('active');
  document.body.style.overflow = '';
  setTimeout(() => {
    document.getElementById('modalBody').innerHTML = '';
  }, 250);
}

// ── Todo / Engineering Detail Modal ───────────────────
function openTodoModal(task) {
  const statusBadge = `<span class="badge ${badgeClass(task.status)}">${esc(task.status)}</span>`;
  const bucketBadge = `<span class="badge badge-bucket">${esc(task.bucket || '-')}</span>`;

  let bodyHtml = '';

  if (task.module) {
    bodyHtml += `
      <div class="modal-meta-row">
        ${statusBadge} ${bucketBadge}
      </div>
      <div class="modal-meta-row" style="font-size:0.82rem;color:var(--text-tertiary);">
        <span>Module: <strong style="color:var(--text-secondary);">${esc(task.module)}</strong></span>
        ${task.size ? `<span>· size: <strong style="color:var(--text-secondary);">${esc(task.size)}</strong></span>` : ''}
        ${task.effort ? `<span>· effort: <strong style="color:var(--text-secondary);">${esc(task.effort)}</strong></span>` : ''}
      </div>
    `;
  } else {
    bodyHtml += `<div class="modal-meta-row">${statusBadge} ${bucketBadge}</div>`;
  }

  if (task.serves) {
    const serves = Array.isArray(task.serves) ? task.serves : [task.serves];
    bodyHtml += `
      <div class="modal-section">
        <h4>Serves</h4>
        <div style="display:flex;gap:0.4rem;flex-wrap:wrap;">
          ${serves.map(s => `<span class="badge badge-kind">${esc(s)}</span>`).join('')}
        </div>
      </div>
    `;
  }

  if (task.accept) {
    const accept = Array.isArray(task.accept) ? task.accept : [task.accept];
    bodyHtml += `
      <div class="modal-section">
        <h4>Acceptance Criteria</h4>
        <ul>
          ${accept.map(a => `<li>${inline(a)}</li>`).join('')}
        </ul>
      </div>
    `;
  }

  if (task.body && task.body.length) {
    bodyHtml += `
      <div class="modal-section">
        <h4>Description</h4>
        ${task.body.map(p => `<p>${inline(p)}</p>`).join('')}
      </div>
    `;
  }

  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(task.title)}</div>
      <div class="modal-subtitle">${esc(task.id)}</div>
    </div>
    ${bodyHtml}
  `);
}

// ── Research Detail Modal ─────────────────────────────
function openResearchModal(r) {
  let bodyHtml = `
    <div class="modal-meta-row">
      <span class="badge ${badgeClass(r.status)}">${esc(r.status)}</span>
      ${r.kind ? `<span class="badge badge-kind">${esc(r.kind)}</span>` : ''}
      ${r.module ? `<span class="badge badge-bucket">${esc(r.module)}</span>` : ''}
    </div>
  `;

  if (r.hypothesis) {
    bodyHtml += `
      <div class="modal-section">
        <h4>Hypothesis</h4>
        <p style="font-style:italic;color:var(--text-primary);">${inline(r.hypothesis)}</p>
      </div>
    `;
  }

  if (r.body && r.body.length) {
    bodyHtml += `
      <div class="modal-section">
        <h4>Details</h4>
        ${r.body.map(p => `<p>${inline(p)}</p>`).join('')}
      </div>
    `;
  }

  if (r.depends_on && r.depends_on.length) {
    const deps = Array.isArray(r.depends_on) ? r.depends_on : [r.depends_on];
    bodyHtml += `
      <div class="modal-section">
        <h4>Dependencies</h4>
        <ul>
          ${deps.map(d => `<li>${esc(d)}</li>`).join('')}
        </ul>
      </div>
    `;
  }

  if (r.fields) {
    const f = r.fields;
    const fieldItems = [];
    if (f.input) fieldItems.push(`<li><strong>Input:</strong> ${esc(f.input)}</li>`);
    if (f.output) fieldItems.push(`<li><strong>Output:</strong> ${esc(f.output)}</li>`);
    if (f.accept) fieldItems.push(`<li><strong>Accept:</strong> ${esc(f.accept)}</li>`);
    if (f.note) fieldItems.push(`<li><strong>Note:</strong> ${esc(f.note)}</li>`);
    if (fieldItems.length) {
      bodyHtml += `
        <div class="modal-section">
          <h4>Fields</h4>
          <ul>${fieldItems.join('')}</ul>
        </div>
      `;
    }
  }

  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(r.title)}</div>
      ${r.codename ? `<div class="modal-subtitle">${esc(r.codename)}</div>` : ''}
      <div style="font-size:0.8rem;color:var(--text-muted);margin-top:0.3rem;font-family:var(--font-mono);">${esc(r.id)}</div>
    </div>
    ${bodyHtml}
  `);
}

// ── Note HTML Modal ───────────────────────────────────
async function openNoteModal(path) {
  showModal(`
    <div class="loading-state" style="padding:3rem 0;">
      <div class="spinner"></div>
      <p>Loading note...</p>
    </div>
  `);

  try {
    const res = await fetch(API_BASE + '/api/projects/' + encodeURIComponent(currentProject) + '/data/' + encodeURIComponent(path));
    if (res.ok) {
      const json = await res.json();
      const raw = json.content || '';
      // Extract <body> content so inline styles don't override the theme
      const bodyMatch = raw.match(/<body[^>]*>([\s\S]*)<\/body>/i);
      const html = bodyMatch ? bodyMatch[1] : (raw || '<div class="empty-state">Note is empty</div>');
      const titleMatch = raw.match(/<title>([^<]*)<\/title>/i) || raw.match(/<h1[^>]*>([^<]*)<\/h1>/i);
      const title = titleMatch ? titleMatch[1].trim() : esc(path);

      document.getElementById('modalBody').innerHTML = `
        <div class="modal-header">
          <div class="modal-title">${esc(title)}</div>
          <div style="font-size:0.8rem;color:var(--text-muted);font-family:var(--font-mono);">${esc(path)}</div>
        </div>
        <div class="modal-html-content">${html}</div>
      `;
    } else {
      document.getElementById('modalBody').innerHTML = `
        <div class="empty-state" style="padding:3rem 0;">Failed to load note (HTTP ${res.status})</div>
      `;
    }
  } catch (e) {
    document.getElementById('modalBody').innerHTML = `
      <div class="empty-state" style="padding:3rem 0;">Failed to load: ${esc(e.message)}</div>
    `;
  }
}

// ── Open Folder ───────────────────────────────────────
async function openFolder(pathOverride) {
  const inputEl = document.getElementById('folderInput');
  const path = pathOverride || (inputEl ? inputEl.value.trim() : '');
  if (!path) return;

  const btn = document.getElementById('folderBtn');
  const errEl = document.getElementById('landingError');

  if (btn) { btn.disabled = true; btn.textContent = 'Loading...'; }
  if (errEl) errEl.textContent = '';

  try {
    const res = await fetch(API_BASE + '/api/open', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path }),
    });
    const json = await res.json();
    if (json.error) throw new Error(json.error);
    // Reload so boot() picks up the new project
    location.reload();
  } catch (e) {
    if (errEl) errEl.textContent = 'Error: ' + e.message;
    if (btn) { btn.disabled = false; btn.textContent = 'Open'; }
    // Also surface in a prompt-based flow
    if (!inputEl) alert('Error: ' + e.message);
  }
}

// ── Boot ──────────────────────────────────────────────
let currentProject = null;

async function boot() {
  initTheme();
  document.getElementById('themeToggle')?.addEventListener('click', toggleTheme);

  const select = document.getElementById('projectSelect');

  // Modal close handlers
  document.getElementById('modalClose').addEventListener('click', hideModal);
  document.getElementById('modalOverlay').addEventListener('click', (e) => {
    if (e.target === e.currentTarget) hideModal();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') hideModal();
  });

  // Load project list
  const projects = await loadProjects();

  if (!projects.length) {
    // Show landing, hide sections
    document.getElementById('landing').style.display = '';
    document.querySelectorAll('.section').forEach(s => s.style.display = 'none');
    // Wire up open button
    document.getElementById('folderBtn').addEventListener('click', () => openFolder());
    document.getElementById('folderInput').addEventListener('keydown', e => {
      if (e.key === 'Enter') openFolder();
    });
    return;
  }

  select.innerHTML = '<option value="" disabled>Select project...</option>' +
    projects.map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');

  // Default to first project
  currentProject = projects[0].id;
  select.value = currentProject;
  await loadAndRender(currentProject);

  // Project switch handler
  select.addEventListener('change', async () => {
    currentProject = select.value;
    await loadAndRender(currentProject);
  });

  // "+" add-folder button: toggle the inline folder bar
  const addBtn = document.getElementById('addFolder');
  const folderBar = document.getElementById('folderBar');
  const folderBarInput = document.getElementById('folderBarInput');
  const folderBarBtn = document.getElementById('folderBarBtn');
  const folderBarClose = document.getElementById('folderBarClose');
  const folderBarErr = document.getElementById('folderBarErr');

  if (addBtn && folderBar) {
    addBtn.addEventListener('click', () => {
      const visible = folderBar.style.display !== 'none';
      folderBar.style.display = visible ? 'none' : '';
      if (!visible) { folderBarInput.value = ''; folderBarErr.textContent = ''; folderBarInput.focus(); }
    });

    folderBarClose.addEventListener('click', () => { folderBar.style.display = 'none'; });

    async function submitFolderBar() {
      const path = folderBarInput.value.trim();
      if (!path) return;
      folderBarBtn.disabled = true; folderBarBtn.textContent = '加载中…';
      folderBarErr.textContent = '';
      try {
        const res = await fetch(API_BASE + '/api/open', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path }),
        });
        const json = await res.json();
        if (json.error) throw new Error(json.error);
        location.reload();
      } catch (e) {
        folderBarErr.textContent = e.message;
        folderBarBtn.disabled = false; folderBarBtn.textContent = '打开';
      }
    }

    folderBarBtn.addEventListener('click', submitFolderBar);
    folderBarInput.addEventListener('keydown', e => {
      if (e.key === 'Enter') submitFolderBar();
      if (e.key === 'Escape') { folderBar.style.display = 'none'; }
    });
  }
}

async function loadAndRender(projectId) {
  // Show loading in all sections
  const loadingHtml = `
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Loading...</p>
    </div>
  `;
  document.getElementById('todoBody').innerHTML = loadingHtml;
  document.getElementById('researchBody').innerHTML = loadingHtml;
  document.getElementById('engineeringBody').innerHTML = loadingHtml;
  document.getElementById('notesBody').innerHTML = loadingHtml;

  try {
    const data = await loadProjectData(projectId);
    renderAll(data);
  } catch (e) {
    const errHtml = `<div class="empty-state" style="color:var(--error);">Failed to load: ${esc(e.message)}</div>`;
    document.getElementById('todoBody').innerHTML = errHtml;
    document.getElementById('researchBody').innerHTML = errHtml;
    document.getElementById('engineeringBody').innerHTML = errHtml;
    document.getElementById('notesBody').innerHTML = errHtml;
    console.error(e);
  }
}

boot().catch(e => {
  console.error('Boot error:', e);
  document.getElementById('todoBody').innerHTML = `<div class="empty-state" style="color:var(--error);">Startup failed: ${esc(e.message)}</div>`;
});
