// ── Utilities ────────────────────────────────────────────────────────────────

function esc(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function inline(s) {
  if (!s) return '';
  // Escape first so user content cannot inject markup, then apply the
  // limited **bold** / `code` markdown on the escaped string.
  return esc(s)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`\n]+)`/g, '<code>$1</code>');
}

function textToHtml(text) {
  if (/<[a-zA-Z]/.test(text)) return text;
  return text.split(/\n{2,}/).filter(p=>p.trim()).map(p=>`<p>${
    esc(p.trim()).replace(/\n/g,'<br>')
      .replace(/\*\*([^*]+)\*\*/g,'<strong>$1</strong>')
      .replace(/`([^`]+)`/g,'<code>$1</code>')
  }</p>`).join('\n');
}

// Notes legitimately store HTML (including migrated documents), so we cannot
// simply escape body_html. Scrub the active vectors instead: drop <script>/
// <style>/<iframe>/<object> elements, inline event handlers, and
// javascript:/data: URLs, parsing in an inert document that does not execute.
function sanitizeHtml(html) {
  const doc = new DOMParser().parseFromString(String(html ?? ''), 'text/html');
  doc.querySelectorAll('script, style, iframe, object, embed, link, meta, base, form')
    .forEach(el => el.remove());
  doc.querySelectorAll('*').forEach(el => {
    for (const attr of [...el.attributes]) {
      const name = attr.name.toLowerCase();
      const val = attr.value.replace(/\s+/g, '').toLowerCase();
      if (name.startsWith('on')) el.removeAttribute(attr.name);
      else if ((name === 'href' || name === 'src' || name === 'xlink:href')
               && (val.startsWith('javascript:') || val.startsWith('data:'))) {
        el.removeAttribute(attr.name);
      }
    }
  });
  return doc.body.innerHTML;
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

// ── New project form ──────────────────────────────────────────────────────────

function openNewProjectForm() {
  showFormModal(`
    <div class="form-header"><div class="form-title">New project</div></div>
    <div class="form-group">
      <label class="form-label">Git repository folder (optional)</label>
      <input id="f-folder" class="form-input" placeholder="/Users/you/MyProject" spellcheck="false" autocomplete="off">
      <div style="font-size:0.78rem;color:var(--text-muted);margin-top:.25rem">Auto-fills project name from folder name</div>
    </div>
    <div class="form-group">
      <label class="form-label">Project name *</label>
      <input id="f-name" class="form-input" placeholder="My Project">
    </div>
    <div class="form-group">
      <label class="form-label">Tagline (optional)</label>
      <input id="f-tagline" class="form-input" placeholder="Short description">
    </div>
    <div class="form-actions">
      <button id="fSave" class="form-save-btn">Create</button>
      <button id="fCancel" class="form-cancel-btn">Cancel</button>
      <span id="fErr" class="form-err"></span>
    </div>
  `);

  document.getElementById('f-folder').addEventListener('input', () => {
    const folder = document.getElementById('f-folder').value.trim().replace(/\\/g, '/');
    const parts = folder.split('/').filter(Boolean);
    const last = parts[parts.length - 1] || '';
    if (last) document.getElementById('f-name').value = last;
  });

  document.getElementById('fCancel').addEventListener('click', hideFormModal);

  document.getElementById('fSave').addEventListener('click', async () => {
    const errEl = document.getElementById('fErr');
    const name = document.getElementById('f-name').value.trim();
    if (!name) { errEl.textContent = 'Name is required'; return; }
    const payload = {
      name,
      tagline: document.getElementById('f-tagline').value.trim(),
      repo_path: document.getElementById('f-folder').value.trim(),
    };
    try {
      const result = await api('POST', '/api/projects', payload);
      hideFormModal();
      location.href = '/' + result.project.id;
    } catch(e) { errEl.textContent = e.message; }
  });
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

let pid = null;
let _allTasks = [];
let _taskFilter = 'todo';
let _currentWeekMonday = mondayOf(new Date());

// ── Week helpers ──────────────────────────────────────────────────────────────

function mondayOf(date) {
  const d = new Date(date);
  const day = d.getDay() || 7;
  d.setDate(d.getDate() - day + 1);
  d.setHours(0, 0, 0, 0);
  return d;
}

function getISOWeek(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return {
    year: d.getUTCFullYear(),
    week: Math.ceil(((d - yearStart) / 86400000 + 1) / 7),
  };
}

function weekId(monday) {
  const iso = getISOWeek(monday);
  return `${iso.year}-W${String(iso.week).padStart(2, '0')}`;
}

function weekLabel(monday) {
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  const fmt = (d, opts) => new Intl.DateTimeFormat('en-US', opts).format(d);
  const mo = fmt(monday, { month: 'short', day: 'numeric' });
  const su = fmt(sunday, { month: 'short', day: 'numeric', year: 'numeric' });
  const { week } = getISOWeek(monday);
  return `Week ${week} · ${mo} – ${su}`;
}

function shiftWeek(monday, delta) {
  const d = new Date(monday);
  d.setDate(d.getDate() + delta * 7);
  return d;
}

// ── Weekly Workbench ──────────────────────────────────────────────────────────

async function loadWeekly() {
  document.getElementById('weekLabel').textContent = weekLabel(_currentWeekMonday);
  const body = document.getElementById('weeklyBody');
  body.innerHTML = '<div class="loading-state"><div class="spinner"></div><p>Loading...</p></div>';
  const wid = weekId(_currentWeekMonday);
  try {
    const [weekData, features] = await Promise.all([
      api('GET', `/api/projects/${encodeURIComponent(pid)}/weeks/${encodeURIComponent(wid)}`),
      api('GET', `/api/projects/${encodeURIComponent(pid)}/features?week_id=${encodeURIComponent(wid)}`),
    ]);
    renderWeekly(weekData, features);
  } catch(e) {
    body.innerHTML = `<div class="empty-state" style="color:var(--error)">${esc(e.message)}</div>`;
  }
}

function renderWeekly(weekData, features) {
  const wid = weekData.week_id;
  const hasGoal = weekData.goal_title || weekData.goal_body;

  const goalHtml = hasGoal ? `
    <div class="weekly-goal-card">
      <div class="weekly-goal-meta">
        <span class="weekly-goal-eyebrow">Weekly goal</span>
        <button class="weekly-goal-edit-btn" data-wid="${esc(wid)}">Edit</button>
      </div>
      <div class="weekly-goal-title">${esc(weekData.goal_title)}</div>
      ${weekData.goal_body ? `<div class="weekly-goal-body">${esc(weekData.goal_body)}</div>` : ''}
    </div>
  ` : `
    <div class="weekly-goal-empty" data-wid="${esc(wid)}">
      <span class="weekly-goal-empty-icon">+</span>
      <span>Set weekly goal</span>
    </div>
  `;

  const featureCards = features.map(f => `
    <div class="feature-card feature-status-${esc(f.status)}" data-fid="${esc(f.id)}">
      <div class="feature-card-title">${esc(f.title)}</div>
      <div class="feature-card-status">
        <span class="feature-status-dot"></span>
        <span class="feature-status-label">${esc(f.status)}</span>
      </div>
    </div>
  `).join('');

  document.getElementById('weeklyBody').innerHTML = `
    <div class="weekly-content">
      ${goalHtml}
      <div class="weekly-features">
        <div class="weekly-features-header">
          <span class="weekly-features-label">Focus areas</span>
          <button class="weekly-add-feature-btn" data-wid="${esc(wid)}">+</button>
        </div>
        <div class="weekly-features-grid">
          ${featureCards}
          ${features.length === 0 ? '<span class="weekly-features-hint">No focus areas yet — add one with +</span>' : ''}
        </div>
      </div>
    </div>
  `;

  // Goal card click
  document.querySelector('.weekly-goal-edit-btn, .weekly-goal-empty')
    ?.addEventListener('click', () => openGoalForm(weekData));

  // Feature card clicks
  document.querySelectorAll('.feature-card').forEach(card => {
    card.addEventListener('click', () => {
      const f = features.find(x => x.id === card.dataset.fid);
      if (f) openFeatureForm(f, wid);
    });
  });

  // Add feature button
  document.querySelector('.weekly-add-feature-btn')
    ?.addEventListener('click', () => openFeatureForm(null, wid));
}

function openGoalForm(weekData) {
  const wid = weekData.week_id;
  showFormModal(`
    <div class="form-header"><div class="form-title">Weekly goal</div></div>
    <div class="form-group">
      <label class="form-label">Title</label>
      <input id="f-gtitle" class="form-input" value="${esc(weekData.goal_title)}" placeholder="This week I'm focused on…">
    </div>
    <div class="form-group">
      <label class="form-label">Details (optional)</label>
      <textarea id="f-gbody" class="form-textarea" rows="4" placeholder="What specifically, why it matters, blockers…">${esc(weekData.goal_body)}</textarea>
    </div>
    <div class="form-actions">
      <button id="fSave" class="form-save-btn">Save</button>
      <button id="fCancel" class="form-cancel-btn">Cancel</button>
      <span id="fErr" class="form-err"></span>
    </div>
  `);
  document.getElementById('fCancel').addEventListener('click', hideFormModal);
  document.getElementById('fSave').addEventListener('click', async () => {
    try {
      await api('PUT', `/api/projects/${encodeURIComponent(pid)}/weeks/${encodeURIComponent(wid)}`, {
        goal_title: document.getElementById('f-gtitle').value.trim(),
        goal_body: document.getElementById('f-gbody').value.trim(),
        date_start: weekData.date_start || _currentWeekMonday.toISOString().split('T')[0],
      });
      hideFormModal();
      loadWeekly();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
}

const FEATURE_STATUSES = ['todo', 'done', 'skipped'];

function openFeatureForm(feature, wid) {
  const f = feature || {};
  const isNew = !feature;
  showFormModal(`
    <div class="form-header"><div class="form-title">${isNew ? 'Add focus area' : 'Edit focus area'}</div></div>
    <div class="form-group">
      <label class="form-label">Title *</label>
      <input id="f-ftitle" class="form-input" value="${esc(f.title||'')}" placeholder="What are you building or fixing?">
    </div>
    <div class="form-group">
      <label class="form-label">Description (optional)</label>
      <textarea id="f-fdesc" class="form-textarea" rows="3" placeholder="More details…">${esc(f.description||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Status</label>
      <select id="f-fstatus" class="form-select">
        ${FEATURE_STATUSES.map(s=>`<option value="${s}" ${(f.status||'todo')===s?'selected':''}>${s}</option>`).join('')}
      </select>
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
    const title = document.getElementById('f-ftitle').value.trim();
    if (!title) { document.getElementById('fErr').textContent = 'Title is required'; return; }
    const payload = {
      title,
      description: document.getElementById('f-fdesc').value.trim(),
      status: document.getElementById('f-fstatus').value,
      week_id: wid,
    };
    try {
      if (isNew) {
        await api('POST', `/api/projects/${encodeURIComponent(pid)}/features`, payload);
      } else {
        await api('PUT', `/api/projects/${encodeURIComponent(pid)}/features/${encodeURIComponent(feature.id)}`, payload);
      }
      hideFormModal();
      loadWeekly();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
  document.getElementById('fDelete')?.addEventListener('click', async () => {
    if (!confirm(`Delete "${feature.title}"?`)) return;
    try {
      await api('DELETE', `/api/projects/${encodeURIComponent(pid)}/features/${encodeURIComponent(feature.id)}`);
      hideFormModal();
      loadWeekly();
    } catch(e) { document.getElementById('fErr').textContent = e.message; }
  });
}

// ── Tasks section ─────────────────────────────────────────────────────────────

function taskStatusGroup(status) {
  if (['open', 'in-progress', 'blocked', 'todo'].includes(status)) return 'todo';
  if (status === 'done') return 'done';
  if (status === 'skipped') return 'skipped';
  return 'todo';
}

const PRIORITY_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };

function applyTaskFilter() {
  let visible = _allTasks;
  if (_taskFilter === 'todo') visible = _allTasks.filter(t => taskStatusGroup(t.status) === 'todo');
  else if (_taskFilter === 'done') visible = _allTasks.filter(t => taskStatusGroup(t.status) === 'done');
  else if (_taskFilter === 'skipped') visible = _allTasks.filter(t => taskStatusGroup(t.status) === 'skipped');

  // Sort by priority then date_added
  visible = [...visible].sort((a, b) =>
    (PRIORITY_ORDER[a.priority] ?? 2) - (PRIORITY_ORDER[b.priority] ?? 2)
  );

  const total = _taskFilter === '' ? _allTasks.length : visible.length;
  document.getElementById('tasksCount').textContent =
    _taskFilter === '' ? `${total} total` : `${visible.length} / ${_allTasks.length}`;

  renderTasks(visible);
}

async function loadTasks() {
  const body = document.getElementById('tasksBody');
  body.innerHTML = '<div class="loading-state"><div class="spinner"></div><p>Loading...</p></div>';
  try {
    _allTasks = await api('GET', `/api/projects/${encodeURIComponent(pid)}/tasks`);
    applyTaskFilter();
  } catch(e) {
    body.innerHTML = `<div class="empty-state" style="color:var(--error)">${esc(e.message)}</div>`;
  }
}

function renderTasks(tasks) {
  const body = document.getElementById('tasksBody');

  if (!tasks.length) {
    const hint = _taskFilter === 'todo' ? 'No open tasks' :
                 _taskFilter === 'done' ? 'No completed tasks' :
                 _taskFilter === 'skipped' ? 'No skipped tasks' : 'No tasks yet';
    body.innerHTML = `<div class="empty-state">${hint}</div>`;
    return;
  }

  body.innerHTML = `<div class="task-grid">${tasks.map(t => {
    const tags = (t.tags || []).slice(0, 4);
    const extraTags = (t.tags || []).length - 4;
    const prio = t.priority || 'medium';
    const sg = taskStatusGroup(t.status);
    const descRaw = (t.description || '').replace(/<[^>]+>/g, '').trim();
    return `
      <div class="task-card priority-${esc(prio)} task-status-${esc(sg)}" data-task-id="${esc(t.id)}">
        <div class="task-card-body">
          <div class="task-card-title">${esc(t.title)}</div>
          ${descRaw ? `<div class="task-card-desc">${esc(descRaw)}</div>` : ''}
        </div>
        <div class="task-card-footer">
          <div class="task-card-tags">
            ${tags.map(tag=>`<span class="task-tag">#${esc(tag)}</span>`).join('')}
            ${extraTags > 0 ? `<span class="task-tag task-tag-more">+${extraTags}</span>` : ''}
          </div>
          <div class="task-card-meta">
            ${prio === 'critical' || prio === 'high' ? `<span class="task-priority-pip priority-${esc(prio)}"></span>` : ''}
            <span class="task-status-pip status-${esc(sg)}"></span>
          </div>
        </div>
      </div>
    `;
  }).join('')}</div>`;

  body.querySelectorAll('.task-card').forEach(card => {
    card.addEventListener('click', () => {
      const task = _allTasks.find(t => t.id === card.dataset.taskId);
      if (task) openTaskModal(task);
    });
  });
}

function openTaskModal(task) {
  const prio = task.priority || 'medium';
  const statusGroup = taskStatusGroup(task.status);
  const badgeCls = statusGroup === 'done' ? 'badge-done' :
                   statusGroup === 'skipped' ? 'badge-skipped' : 'badge-open';
  const PRIO_LABEL = { critical: '!! critical', high: '! high', medium: 'medium', low: 'low' };
  showModal(`
    <div class="modal-header">
      <div class="modal-title">${esc(task.title)}</div>
      <div class="modal-subtitle" style="font-family:var(--font-mono)">${esc(task.id)}</div>
    </div>
    <div class="modal-meta-row">
      <span class="badge ${badgeCls}">${esc(task.status)}</span>
      <span class="task-prio-label priority-${esc(prio)}">${esc(PRIO_LABEL[prio] || prio)}</span>
      ${(task.tags||[]).map(tag=>`<span class="task-tag">#${esc(tag)}</span>`).join('')}
    </div>
    ${task.description ? `<div class="modal-section"><h4>Description</h4><p>${inline(task.description)}</p></div>` : ''}
    ${task.note ? `<div class="modal-section"><h4>Note</h4><p>${inline(task.note)}</p></div>` : ''}
    ${task.output ? `<div class="modal-section"><h4>Expected output</h4><p>${inline(task.output)}</p></div>` : ''}
    ${task.acceptance ? `<div class="modal-section"><h4>Acceptance criteria</h4><p>${inline(task.acceptance)}</p></div>` : ''}
    <div class="modal-edit-row">
      <button class="modal-edit-btn" id="modalEditTask">Edit</button>
    </div>
  `);
  document.getElementById('modalEditTask').addEventListener('click', () => {
    hideModal(); openTaskForm(task);
  });
}

const PRIORITIES = ['low', 'medium', 'high', 'critical'];
const TASK_STATUSES = ['todo', 'done', 'skipped'];

function openTaskForm(task) {
  const t = task || {};
  const isNew = !task;
  const formStatus = ['done', 'skipped'].includes(t.status) ? t.status : 'todo';
  showFormModal(`
    <div class="form-header"><div class="form-title">${isNew ? 'New task' : 'Edit task'}</div></div>
    <div class="form-group">
      <label class="form-label">Title *</label>
      <input id="f-title" class="form-input" value="${esc(t.title||'')}" placeholder="Task title">
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Priority</label>
        <select id="f-priority" class="form-select">
          ${PRIORITIES.map(p=>`<option value="${p}" ${(t.priority||'medium')===p?'selected':''}>${p}</option>`).join('')}
        </select>
      </div>
      <div class="form-group">
        <label class="form-label">Status</label>
        <select id="f-status" class="form-select">
          ${TASK_STATUSES.map(s=>`<option value="${s}" ${formStatus===s?'selected':''}>${s}</option>`).join('')}
        </select>
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Tags (comma-separated)</label>
      <input id="f-tags" class="form-input" value="${esc((t.tags||[]).join(', '))}" placeholder="bug, ui, infra">
    </div>
    <div class="form-group">
      <label class="form-label">Description</label>
      <textarea id="f-desc" class="form-textarea" rows="3">${esc(t.description||'')}</textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Note</label>
      <textarea id="f-note" class="form-textarea" rows="2">${esc(t.note||'')}</textarea>
    </div>
    <details class="form-advanced">
      <summary class="form-advanced-toggle">Advanced fields</summary>
      <div style="margin-top:0.8rem">
        <div class="form-row">
          <div class="form-group">
            <label class="form-label">Module</label>
            <input id="f-module" class="form-input" value="${esc(t.module||'')}" placeholder="core">
          </div>
          <div class="form-group">
            <label class="form-label">Size</label>
            <input id="f-size" class="form-input" value="${esc(t.size||'M')}" placeholder="M">
          </div>
        </div>
        <div class="form-group">
          <label class="form-label">Expected output</label>
          <textarea id="f-output" class="form-textarea" rows="2">${esc(t.output||'')}</textarea>
        </div>
        <div class="form-group">
          <label class="form-label">Acceptance criteria</label>
          <textarea id="f-accept" class="form-textarea" rows="2">${esc(t.acceptance||'')}</textarea>
        </div>
      </div>
    </details>
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
      priority: document.getElementById('f-priority').value,
      status: document.getElementById('f-status').value,
      tags: document.getElementById('f-tags').value.split(',').map(s=>s.trim()).filter(Boolean),
      description: document.getElementById('f-desc').value.trim(),
      note: document.getElementById('f-note').value.trim(),
      module: document.getElementById('f-module')?.value.trim() || (t.module || ''),
      size: document.getElementById('f-size')?.value.trim() || (t.size || 'M'),
      output: document.getElementById('f-output')?.value.trim() || (t.output || ''),
      acceptance: document.getElementById('f-accept')?.value.trim() || (t.acceptance || ''),
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

function badgeClass(status) {
  return { 'open':'badge-open','in-progress':'badge-in-progress',
           'blocked':'badge-blocked','done':'badge-done' }[status] || 'badge-open';
}

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

const STATUSES = ['open','in-progress','blocked','done'];
const KINDS = ['ANALYSIS','SAFETY','STATIC','NORMALIZATION','MEASUREMENT','INFRA','FEATURE','ENGINEERING'];

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
        <label class="form-label">Depends on (comma-separated)</label>
        <input id="f-depends" class="form-input" value="${esc((item.depends_on||[]).join(', '))}" placeholder="T-01, T-02">
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
    <div class="modal-html-content">${note.body_html ? sanitizeHtml(note.body_html) : '<p style="color:var(--text-muted)">Empty note</p>'}</div>
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
    const payload = { title, body_html: textToHtml(bodyRaw), tags };
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
  await Promise.all([loadWeekly(), loadTasks(), loadResearch(), loadNotes()]);
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

  document.getElementById('newProjectBtn')?.addEventListener('click', openNewProjectForm);

  const urlPid = window.location.pathname.replace(/^\/+/, '').split('/')[0] || '';

  const projects = await api('GET', '/api/projects').then(d=>d.projects||[]).catch(()=>[]);

  if (!projects.length) {
    document.getElementById('landing').style.display = '';
    document.querySelectorAll('.section').forEach(s => s.style.display='none');
    document.getElementById('landingNewBtn')?.addEventListener('click', openNewProjectForm);
    return;
  }

  const validIds = projects.map(p => p.id);
  const select = document.getElementById('projectSelect');
  select.innerHTML = '<option value="" disabled>Select project…</option>' +
    projects.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');

  pid = (urlPid && validIds.includes(urlPid)) ? urlPid : projects[0].id;
  select.value = pid;

  if (window.location.pathname.replace(/^\/+/, '') !== pid) {
    history.replaceState({pid}, '', '/' + pid);
  }

  // Week navigation
  document.getElementById('weekLabel').textContent = weekLabel(_currentWeekMonday);
  document.getElementById('weekPrev').addEventListener('click', () => {
    _currentWeekMonday = shiftWeek(_currentWeekMonday, -1);
    loadWeekly();
  });
  document.getElementById('weekNext').addEventListener('click', () => {
    _currentWeekMonday = shiftWeek(_currentWeekMonday, 1);
    loadWeekly();
  });

  // Task filter tabs
  document.querySelectorAll('.task-filter-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.task-filter-tab').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      _taskFilter = btn.dataset.filter;
      applyTaskFilter();
    });
  });

  await loadDashboard();

  select.addEventListener('change', async () => {
    pid = select.value;
    history.pushState({pid}, '', '/' + pid);
    _currentWeekMonday = mondayOf(new Date());
    document.getElementById('weekLabel').textContent = weekLabel(_currentWeekMonday);
    await loadDashboard();
  });

  window.addEventListener('popstate', async (e) => {
    const newPid = e.state?.pid || window.location.pathname.replace(/^\/+/, '').split('/')[0] || projects[0].id;
    if (validIds.includes(newPid)) {
      pid = newPid;
      select.value = pid;
      _currentWeekMonday = mondayOf(new Date());
      await loadDashboard();
    }
  });

  document.getElementById('newTaskBtn')?.addEventListener('click', () => openTaskForm(null));
  document.getElementById('newResearchBtn')?.addEventListener('click', () => openResearchForm(null));
  document.getElementById('newNoteBtn')?.addEventListener('click', () => openNoteForm(null));
}

boot().catch(e => {
  console.error('Boot error:', e);
  document.getElementById('tasksBody').innerHTML =
    `<div class="empty-state" style="color:var(--error)">Startup failed: ${esc(e.message)}</div>`;
});
