// ── Utilities ────────────────────────────────────────────────────────────────

function esc(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function inline(s) {
  if (!s) return '';
  return String(s)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`\n]+)`/g, '<code>$1</code>');
}

function badgeClass(status) {
  return { 'open':'badge-open','in-progress':'badge-in-progress',
           'blocked':'badge-blocked','done':'badge-done' }[status] || 'badge-open';
}

function bucketLineVar(bucket) {
  const n = parseInt((bucket||'').replace(/^P/,''),10);
  return (n>=0&&n<=5) ? `var(--p${n}-line)` : 'var(--border-default)';
}

function textToHtml(text) {
  if (/<[a-zA-Z]/.test(text)) return text;
  return text.split(/\n{2,}/).filter(p=>p.trim()).map(p=>`<p>${
    p.trim().replace(/\n/g,'<br>')
      .replace(/\*\*([^*]+)\*\*/g,'<strong>$1</strong>')
      .replace(/`([^`]+)`/g,'<code>$1</code>')
  }</p>`).join('\n');
}

// ── API ───────────────────────────────────────────────────────────────────────

const BASE = '';

async function api(method, path, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(BASE + path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

// ── Theme ─────────────────────────────────────────────────────────────────────

function initTheme() {
  const saved = localStorage.getItem('docsbot:theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
}

function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('docsbot:theme', next);
}

// ── Recent paths ──────────────────────────────────────────────────────────────

function getRecentPaths() {
  try { return JSON.parse(localStorage.getItem('docsbot:recentPaths') || '[]'); } catch { return []; }
}
function addRecentPath(path) {
  const list = [path, ...getRecentPaths().filter(p=>p!==path)].slice(0,10);
  localStorage.setItem('docsbot:recentPaths', JSON.stringify(list));
}
function populateRecentDatalist() {
  const dl = document.getElementById('recentPathsList');
  if (dl) dl.innerHTML = getRecentPaths().map(p=>`<option value="${esc(p)}">`).join('');
}

// ── Modals ────────────────────────────────────────────────────────────────────

function showModal(html) {
  document.getElementById('modalBody').innerHTML = html;
  document.getElementById('modalOverlay').classList.add('active');
  document.body.style.overflow = 'hidden';
}
function hideModal() {
  document.getElementById('modalOverlay').classList.remove('active');
  document.body.style.overflow = '';
  setTimeout(() => { document.getElementById('modalBody').innerHTML = ''; }, 250);
}
function showFormModal(html) {
  document.getElementById('formBody').innerHTML = html;
  document.getElementById('formOverlay').classList.add('active');
  document.body.style.overflow = 'hidden';
}
function hideFormModal() {
  document.getElementById('formOverlay').classList.remove('active');
  document.body.style.overflow = '';
}

// ── State ─────────────────────────────────────────────────────────────────────

let pid = null; // current project id

// ── Tasks section ─────────────────────────────────────────────────────────────

async function loadTasks() {
  const body = document.getElementById('tasksBody');
  body.innerHTML = '<div class="loading-state"><div class="spinner"></div><p>Loading...</p></div>';
  try {
    const [tasks, buckets] = await Promise.all([
      api('GET', `/api/projects/${encodeURIComponent(pid)}/tasks`),
      api('GET', `/api/projects/${encodeURIComponent(pid)}/buckets`),
    ]);
    renderTasks(tasks, buckets);
  } catch(e) {
    body.innerHTML = `<div class="empty-state" style="color:var(--error)">${esc(e.message)}</div>`;
  }
}

function renderTasks(tasks, buckets) {
  const body = document.getElementById('tasksBody');
  document.getElementById('tasksCount').textContent = `${tasks.length} items`;

  if (!tasks.length) {
    body.innerHTML = '<div class="empty-state">No tasks yet</div>';
    return;
  }

  const byBucket = {};
  for (const b of buckets) byBucket[b.p] = [];
  for (const t of tasks) {
    if (!byBucket[t.bucket]) byBucket[t.bucket] = [];
    byBucket[t.bucket].push(t);
  }

  const bucketMeta = {};
  for (const b of buckets) bucketMeta[b.p] = b;

  body.innerHTML = Object.entries(byBucket)
    .filter(([,items]) => items.length > 0)
    .map(([p, items]) => {
      const b = bucketMeta[p] || { label: p };
      return `
        <div class="module-group">
          <div class="module-group-header">
            <span class="module-group-title" style="color:${`var(--p${p.replace('P','')||0})`}">${esc(p)}</span>
            <span style="font-size:0.78rem;color:var(--text-muted);margin-left:0.4rem;">${esc(b.label||'')}</span>
            <span class="module-group-count">${items.length}</span>
          </div>
          <div class="module-group-grid">
            ${items.map(t => `
              <div class="compact-card task-card" data-task-id="${esc(t.id)}" style="--bucket-line:${bucketLineVar(t.bucket)};">
                <div class="compact-card-title">${esc(t.title)}</div>
                <div class="compact-card-meta">
                  <span class="badge ${badgeClass(t.status)}">${esc(t.status)}</span>
                  ${t.module ? `<span style="font-size:0.72rem;color:var(--text-muted);">${esc(t.module)}</span>` : ''}
                  ${t.size ? `<span style="font-size:0.72rem;color:var(--text-muted);font-family:var(--font-mono);">${esc(t.size)}</span>` : ''}
                </div>
              </div>
            `).join('')}
          </div>
        </div>`;
    }).join('');

  body.querySelectorAll('.task-card').forEach(card => {
    card.addEventListener('click', async () => {
      const task = tasks.find(t => t.id === card.dataset.taskId);
      if (task) openTaskModal(task, buckets);
    });
  });
}

function openTaskModal(task, buckets) {
  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(task.title)}</div>
      <div class="modal-subtitle" style="font-family:var(--font-mono)">${esc(task.id)}</div>
    </div>
    <div class="modal-meta-row">
      <span class="badge ${badgeClass(task.status)}">${esc(task.status)}</span>
      <span class="badge badge-bucket">${esc(task.bucket)}</span>
      ${task.module ? `<span class="badge badge-kind">${esc(task.module)}</span>` : ''}
      ${task.size ? `<span style="font-size:0.8rem;color:var(--text-muted);font-family:var(--font-mono);">${esc(task.size)}${task.effort ? ' · '+esc(task.effort) : ''}</span>` : ''}
    </div>
    ${task.description ? `<div class="modal-section"><h4>Description</h4><p>${inline(task.description)}</p></div>` : ''}
    ${task.output ? `<div class="modal-section"><h4>Expected output</h4><p>${inline(task.output)}</p></div>` : ''}
    ${task.acceptance ? `<div class="modal-section"><h4>Acceptance criteria</h4><p>${inline(task.acceptance)}</p></div>` : ''}
    ${task.note ? `<div class="modal-section"><h4>Note</h4><p>${inline(task.note)}</p></div>` : ''}
    ${(task.serves||[]).length ? `<div class="modal-section"><h4>Serves</h4><div style="display:flex;gap:.4rem;flex-wrap:wrap">${task.serves.map(s=>`<span class="badge badge-kind">${esc(s)}</span>`).join('')}</div></div>` : ''}
    <div class="modal-edit-row">
      <button class="modal-edit-btn" id="modalEditTask">Edit</button>
    </div>
  `);
  document.getElementById('modalEditTask').addEventListener('click', () => {
    hideModal(); openTaskForm(task, buckets);
  });
}

const STATUSES = ['open','in-progress','blocked','done'];
const SIZES = ['XS','S','M','L','XL'];
const KINDS = ['ANALYSIS','SAFETY','STATIC','NORMALIZATION','MEASUREMENT','INFRA','FEATURE','ENGINEERING'];

function openTaskForm(task, buckets) {
  const t = task || {};
  const isNew = !task;
  showFormModal(`
    <div class="form-header"><div class="form-title">${isNew ? 'New task' : 'Edit task'}</div></div>
    <div class="form-group">
      <label class="form-label">Title *</label>
      <input id="f-title" class="form-input" value="${esc(t.title||'')}" placeholder="Task title">
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Bucket</label>
        <select id="f-bucket" class="form-select">
          ${(buckets||[]).map(b=>`<option value="${esc(b.p)}" ${t.bucket===b.p?'selected':''}>${esc(b.p)} — ${esc(b.label)}</option>`).join('')}
        </select>
      </div>
      <div class="form-group">
        <label class="form-label">Module</label>
        <input id="f-module" class="form-input" value="${esc(t.module||'')}" placeholder="core">
      </div>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Size</label>
        <select id="f-size" class="form-select">${SIZES.map(s=>`<option ${t.size===s?'selected':''}>${s}</option>`).join('')}</select>
      </div>
      <div class="form-group">
        <label class="form-label">Effort</label>
        <input id="f-effort" class="form-input" value="${esc(t.effort||'')}" placeholder="1-2 d">
      </div>
      <div class="form-group">
        <label class="form-label">Status</label>
        <select id="f-status" class="form-select">${STATUSES.map(s=>`<option ${t.status===s?'selected':''}>${s}</option>`).join('')}</select>
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Description</label>
      <textarea id="f-desc" class="form-textarea" rows="2">${esc(t.description||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Expected output</label>
      <textarea id="f-output" class="form-textarea" rows="2">${esc(t.output||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Acceptance criteria</label>
      <textarea id="f-accept" class="form-textarea" rows="2">${esc(t.acceptance||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Note</label>
      <textarea id="f-note" class="form-textarea" rows="2">${esc(t.note||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Serves (comma-separated R-ids)</label>
      <input id="f-serves" class="form-input" value="${esc((t.serves||[]).join(', '))}" placeholder="R1, R2">
    </div>
    <div class="form-actions">
      <button id="fSave" class="form-save-btn">Save</button>
      ${!isNew ? '<button id="fDelete" class="form-delete-btn">Delete</button>' : ''}
      <button id="fCancel" class="form-cancel-btn">Cancel</button>
      <span id="fErr" class="form-err"></span>
    </div>
  `);

  document.getElementById('fCancel').addEventListener('click', hideFormModal);

  document.getElementById('fSave').addEventListener('click', async () => {
    const errEl = document.getElementById('fErr');
    const title = document.getElementById('f-title').value.trim();
    if (!title) { errEl.textContent = 'Title is required'; return; }
    const payload = {
      title,
      bucket: document.getElementById('f-bucket').value,
      module: document.getElementById('f-module').value.trim(),
      size: document.getElementById('f-size').value,
      effort: document.getElementById('f-effort').value.trim(),
      status: document.getElementById('f-status').value,
      description: document.getElementById('f-desc').value.trim(),
      output: document.getElementById('f-output').value.trim(),
      acceptance: document.getElementById('f-accept').value.trim(),
      note: document.getElementById('f-note').value.trim(),
      serves: document.getElementById('f-serves').value.split(',').map(s=>s.trim()).filter(Boolean),
    };
    try {
      if (isNew) {
        await api('POST', `/api/projects/${encodeURIComponent(pid)}/tasks`, payload);
      } else {
        await api('PUT', `/api/projects/${encodeURIComponent(pid)}/tasks/${encodeURIComponent(task.id)}`, payload);
      }
      hideFormModal();
      loadTasks();
    } catch(e) { errEl.textContent = e.message; }
  });

  document.getElementById('fDelete')?.addEventListener('click', async () => {
    if (!confirm(`Delete task "${task.title}"?`)) return;
    try {
      await api('DELETE', `/api/projects/${encodeURIComponent(pid)}/tasks/${encodeURIComponent(task.id)}`);
      hideFormModal(); loadTasks();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
}

// ── Research section ──────────────────────────────────────────────────────────

async function loadResearch() {
  const body = document.getElementById('researchBody');
  body.innerHTML = '<div class="loading-state"><div class="spinner"></div><p>Loading...</p></div>';
  try {
    const research = await api('GET', `/api/projects/${encodeURIComponent(pid)}/research`);
    renderResearch(research);
  } catch(e) {
    body.innerHTML = `<div class="empty-state" style="color:var(--error)">${esc(e.message)}</div>`;
  }
}

function renderResearch(items) {
  const body = document.getElementById('researchBody');
  document.getElementById('researchCount').textContent = `${items.length} items`;
  if (!items.length) {
    body.innerHTML = '<div class="empty-state">No research directions yet</div>';
    return;
  }
  const sorted = [...items].sort((a,b) => {
    const o = {'in-progress':0,'blocked':1,'open':2,'done':3};
    return (o[a.status]??9) - (o[b.status]??9);
  });
  body.innerHTML = `<div class="card-grid">${sorted.map(r=>`
    <div class="grid-card research-card" data-research-id="${esc(r.id)}"
         style="--card-accent:${r.status==='in-progress'?'var(--accent)':'var(--border-default)'}">
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
  `).join('')}</div>`;
  body.querySelectorAll('.research-card').forEach(card => {
    card.addEventListener('click', () => {
      const item = sorted.find(r => r.id === card.dataset.researchId);
      if (item) openResearchModal(item);
    });
  });
}

function openResearchModal(r) {
  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(r.title)}</div>
      ${r.codename ? `<div class="modal-subtitle">${esc(r.codename)}</div>` : ''}
      <div style="font-size:0.8rem;color:var(--text-muted);font-family:var(--font-mono)">${esc(r.id)}</div>
    </div>
    <div class="modal-meta-row">
      <span class="badge ${badgeClass(r.status)}">${esc(r.status)}</span>
      ${r.kind ? `<span class="badge badge-kind">${esc(r.kind)}</span>` : ''}
      ${r.module ? `<span class="badge badge-bucket">${esc(r.module)}</span>` : ''}
    </div>
    ${r.hypothesis ? `<div class="modal-section"><h4>Hypothesis</h4><p style="font-style:italic">${inline(r.hypothesis)}</p></div>` : ''}
    ${(r.body||[]).length ? `<div class="modal-section"><h4>Details</h4>${r.body.map(p=>`<p>${inline(p)}</p>`).join('')}</div>` : ''}
    ${(r.depends_on||[]).length ? `<div class="modal-section"><h4>Dependencies</h4><ul>${r.depends_on.map(d=>`<li>${esc(d)}</li>`).join('')}</ul></div>` : ''}
    <div class="modal-edit-row">
      <button class="modal-edit-btn" id="modalEditResearch">Edit</button>
    </div>
  `);
  document.getElementById('modalEditResearch').addEventListener('click', () => {
    hideModal(); openResearchForm(r);
  });
}

function openResearchForm(r) {
  const item = r || {};
  const isNew = !r;
  showFormModal(`
    <div class="form-header"><div class="form-title">${isNew ? 'New research direction' : 'Edit research direction'}</div></div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Codename</label>
        <input id="f-codename" class="form-input" value="${esc(item.codename||'')}" placeholder="MYDIR">
      </div>
      <div class="form-group">
        <label class="form-label">Kind</label>
        <select id="f-kind" class="form-select">${KINDS.map(k=>`<option ${item.kind===k?'selected':''}>${k}</option>`).join('')}</select>
      </div>
      <div class="form-group">
        <label class="form-label">Module</label>
        <input id="f-module" class="form-input" value="${esc(item.module||'')}" placeholder="core">
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Title *</label>
      <input id="f-title" class="form-input" value="${esc(item.title||'')}" placeholder="Research direction title">
    </div>
    <div class="form-group">
      <label class="form-label">Hypothesis</label>
      <textarea id="f-hypothesis" class="form-textarea" rows="2">${esc(item.hypothesis||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Body (one paragraph per line)</label>
      <textarea id="f-body" class="form-textarea" rows="4">${esc((item.body||[]).join('\n'))}</textarea>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Depends on (comma-separated P-ids)</label>
        <input id="f-depends" class="form-input" value="${esc((item.depends_on||[]).join(', '))}" placeholder="P0-01, P1-02">
      </div>
      <div class="form-group">
        <label class="form-label">Status</label>
        <select id="f-status" class="form-select">${STATUSES.map(s=>`<option ${item.status===s?'selected':''}>${s}</option>`).join('')}</select>
      </div>
    </div>
    <div class="form-actions">
      <button id="fSave" class="form-save-btn">Save</button>
      ${!isNew ? '<button id="fDelete" class="form-delete-btn">Delete</button>' : ''}
      <button id="fCancel" class="form-cancel-btn">Cancel</button>
      <span id="fErr" class="form-err"></span>
    </div>
  `);

  document.getElementById('fCancel').addEventListener('click', hideFormModal);

  document.getElementById('fSave').addEventListener('click', async () => {
    const errEl = document.getElementById('fErr');
    const title = document.getElementById('f-title').value.trim();
    if (!title) { errEl.textContent = 'Title is required'; return; }
    const payload = {
      title,
      codename: document.getElementById('f-codename').value.trim().toUpperCase(),
      kind: document.getElementById('f-kind').value,
      module: document.getElementById('f-module').value.trim(),
      hypothesis: document.getElementById('f-hypothesis').value.trim(),
      body: document.getElementById('f-body').value.split('\n').map(s=>s.trim()).filter(Boolean),
      depends_on: document.getElementById('f-depends').value.split(',').map(s=>s.trim()).filter(Boolean),
      status: document.getElementById('f-status').value,
    };
    try {
      if (isNew) {
        await api('POST', `/api/projects/${encodeURIComponent(pid)}/research`, payload);
      } else {
        await api('PUT', `/api/projects/${encodeURIComponent(pid)}/research/${encodeURIComponent(r.id)}`, payload);
      }
      hideFormModal(); loadResearch();
    } catch(e) { errEl.textContent = e.message; }
  });

  document.getElementById('fDelete')?.addEventListener('click', async () => {
    if (!confirm(`Delete research direction "${r.title}"?`)) return;
    try {
      await api('DELETE', `/api/projects/${encodeURIComponent(pid)}/research/${encodeURIComponent(r.id)}`);
      hideFormModal(); loadResearch();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
}

// ── Notes section ─────────────────────────────────────────────────────────────

async function loadNotes() {
  const body = document.getElementById('notesBody');
  body.innerHTML = '<div class="loading-state"><div class="spinner"></div><p>Loading...</p></div>';
  try {
    const notes = await api('GET', `/api/projects/${encodeURIComponent(pid)}/notes`);
    renderNotes(notes);
  } catch(e) {
    body.innerHTML = `<div class="empty-state" style="color:var(--error)">${esc(e.message)}</div>`;
  }
}

function renderNotes(notes) {
  const body = document.getElementById('notesBody');
  document.getElementById('notesCount').textContent = `${notes.length} notes`;
  if (!notes.length) {
    body.innerHTML = '<div class="empty-state">No notes yet</div>';
    return;
  }
  body.innerHTML = `<div class="card-grid">${notes.map(n=>`
    <div class="note-card" data-note-slug="${esc(n.slug)}">
      <div class="note-card-date">${esc(n.date)}</div>
      <div class="note-card-title">${esc(n.title)}</div>
      ${n.excerpt ? `<div class="note-card-excerpt">${esc(n.excerpt)}</div>` : ''}
      ${(n.tags||[]).length ? `<div class="note-tags">${n.tags.map(t=>`<span class="note-tag">${esc(t)}</span>`).join('')}</div>` : ''}
    </div>
  `).join('')}</div>`;
  body.querySelectorAll('.note-card').forEach(card => {
    card.addEventListener('click', async () => {
      const slug = card.dataset.noteSlug;
      const note = await api('GET', `/api/projects/${encodeURIComponent(pid)}/notes/${encodeURIComponent(slug)}`);
      openNoteModal(note);
    });
  });
}

function openNoteModal(note) {
  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(note.title)}</div>
      <div style="font-size:0.8rem;color:var(--text-muted)">${esc(note.date)}${(note.tags||[]).length ? ' · '+note.tags.map(t=>esc(t)).join(', ') : ''}</div>
    </div>
    <div class="modal-html-content">${note.body_html || '<p style="color:var(--text-muted)">Empty note</p>'}</div>
    <div class="modal-edit-row">
      <button class="modal-edit-btn" id="modalEditNote">Edit</button>
    </div>
  `);
  document.getElementById('modalEditNote').addEventListener('click', () => {
    hideModal(); openNoteForm(note);
  });
}

function openNoteForm(note) {
  const n = note || {};
  const isNew = !note;
  // For editing, convert body_html back to plain text for editing (best-effort)
  const bodyText = isNew ? '' : (n.body_html || '').replace(/<\/p>\s*<p>/gi,'\n\n').replace(/<br\s*\/?>/gi,'\n').replace(/<[^>]+>/g,'');

  showFormModal(`
    <div class="form-header"><div class="form-title">${isNew ? 'New note' : 'Edit note'}</div></div>
    <div class="form-group">
      <label class="form-label">Title *</label>
      <input id="f-title" class="form-input" value="${esc(n.title||'')}" placeholder="Note title">
    </div>
    <div class="form-group">
      <label class="form-label">Body (plain text or HTML)</label>
      <textarea id="f-body" class="form-textarea" rows="8" placeholder="Write your note here. Double newline = new paragraph.">${esc(bodyText)}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Tags (comma-separated)</label>
      <input id="f-tags" class="form-input" value="${esc((n.tags||[]).join(', '))}" placeholder="architecture, decisions">
    </div>
    <div class="form-actions">
      <button id="fSave" class="form-save-btn">Save</button>
      ${!isNew ? '<button id="fDelete" class="form-delete-btn">Delete</button>' : ''}
      <button id="fCancel" class="form-cancel-btn">Cancel</button>
      <span id="fErr" class="form-err"></span>
    </div>
  `);

  document.getElementById('fCancel').addEventListener('click', hideFormModal);

  document.getElementById('fSave').addEventListener('click', async () => {
    const errEl = document.getElementById('fErr');
    const title = document.getElementById('f-title').value.trim();
    if (!title) { errEl.textContent = 'Title is required'; return; }
    const bodyRaw = document.getElementById('f-body').value;
    const tags = document.getElementById('f-tags').value.split(',').map(s=>s.trim()).filter(Boolean);
    const payload = {
      title,
      body_html: textToHtml(bodyRaw),
      tags,
    };
    try {
      if (isNew) {
        await api('POST', `/api/projects/${encodeURIComponent(pid)}/notes`, payload);
      } else {
        await api('PUT', `/api/projects/${encodeURIComponent(pid)}/notes/${encodeURIComponent(note.slug)}`, payload);
      }
      hideFormModal(); loadNotes();
    } catch(e) { errEl.textContent = e.message; }
  });

  document.getElementById('fDelete')?.addEventListener('click', async () => {
    if (!confirm(`Delete note "${note.title}"?`)) return;
    try {
      await api('DELETE', `/api/projects/${encodeURIComponent(pid)}/notes/${encodeURIComponent(note.slug)}`);
      hideFormModal(); loadNotes();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

async function loadDashboard() {
  await Promise.all([loadTasks(), loadResearch(), loadNotes()]);
}

// ── Open folder ───────────────────────────────────────────────────────────────

async function openFolder(path) {
  if (!path) return;
  try {
    const data = await api('POST', '/api/open', { path });
    if (data.project) { addRecentPath(path); location.reload(); }
  } catch(e) {
    return e.message;
  }
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function boot() {
  initTheme();
  document.getElementById('themeToggle')?.addEventListener('click', toggleTheme);
  document.getElementById('modalClose').addEventListener('click', hideModal);
  document.getElementById('modalOverlay').addEventListener('click', e => { if (e.target===e.currentTarget) hideModal(); });
  document.getElementById('formClose').addEventListener('click', hideFormModal);
  document.getElementById('formOverlay').addEventListener('click', e => { if (e.target===e.currentTarget) hideFormModal(); });
  document.addEventListener('keydown', e => { if (e.key==='Escape') { hideModal(); hideFormModal(); } });

  const projects = await api('GET', '/api/projects').then(d=>d.projects||[]).catch(()=>[]);

  if (!projects.length) {
    document.getElementById('landing').style.display = '';
    document.querySelectorAll('.section').forEach(s => s.style.display='none');
    populateRecentDatalist();
    const folderBtn = document.getElementById('folderBtn');
    const folderInput = document.getElementById('folderInput');
    const landingError = document.getElementById('landingError');
    folderBtn.addEventListener('click', async () => {
      landingError.textContent = '';
      folderBtn.disabled = true; folderBtn.textContent = 'Opening…';
      const err = await openFolder(folderInput.value.trim());
      if (err) { landingError.textContent = err; folderBtn.disabled=false; folderBtn.textContent='Open'; }
    });
    folderInput.addEventListener('keydown', e => { if (e.key==='Enter') folderBtn.click(); });
    return;
  }

  const select = document.getElementById('projectSelect');
  select.innerHTML = '<option value="" disabled>Select project…</option>' +
    projects.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');
  pid = projects[0].id;
  select.value = pid;
  await loadDashboard();
  select.addEventListener('change', async () => { pid = select.value; await loadDashboard(); });

  // New item buttons
  document.getElementById('newTaskBtn')?.addEventListener('click', async () => {
    const buckets = await api('GET', `/api/projects/${encodeURIComponent(pid)}/buckets`).catch(()=>[]);
    openTaskForm(null, buckets);
  });
  document.getElementById('newResearchBtn')?.addEventListener('click', () => openResearchForm(null));
  document.getElementById('newNoteBtn')?.addEventListener('click', () => openNoteForm(null));

  // Folder bar
  const addBtn = document.getElementById('addFolder');
  const folderBar = document.getElementById('folderBar');
  const folderBarInput = document.getElementById('folderBarInput');
  const folderBarBtn = document.getElementById('folderBarBtn');
  const folderBarClose = document.getElementById('folderBarClose');
  const folderBarErr = document.getElementById('folderBarErr');

  addBtn.addEventListener('click', () => {
    const visible = folderBar.style.display !== 'none';
    folderBar.style.display = visible ? 'none' : '';
    if (!visible) { folderBarInput.value=''; folderBarErr.textContent=''; populateRecentDatalist(); folderBarInput.focus(); }
  });
  folderBarClose.addEventListener('click', () => { folderBar.style.display='none'; });

  async function submitFolderBar() {
    const path = folderBarInput.value.trim();
    if (!path) return;
    folderBarBtn.disabled=true; folderBarBtn.textContent='Opening…'; folderBarErr.textContent='';
    const err = await openFolder(path);
    if (err) { folderBarErr.textContent=err; folderBarBtn.disabled=false; folderBarBtn.textContent='Open'; }
  }
  folderBarBtn.addEventListener('click', submitFolderBar);
  folderBarInput.addEventListener('keydown', e => {
    if (e.key==='Enter') submitFolderBar();
    if (e.key==='Escape') folderBar.style.display='none';
  });
}

boot().catch(e => {
  console.error('Boot error:', e);
  document.getElementById('tasksBody').innerHTML =
    `<div class="empty-state" style="color:var(--error)">Startup failed: ${esc(e.message)}</div>`;
});
