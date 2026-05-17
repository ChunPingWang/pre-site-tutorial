// ── State ──────────────────────────────────────────────────────────────────
const state = {
  features: [],        // [{path, name}]
  results: {},         // {phase: [cucumber features]}
  decision: null,      // presit-decision.json
  current: null,       // currently selected feature path
  dirty: false,
  pipelinePoller: null,
  phasePollers: {},    // {phaseNum: intervalId}
};

// ── DOM refs ───────────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const featureTree = $('feature-tree');
const panelEditor = $('panel-editor');
const panelResults = $('panel-results');
const btnRun = $('btn-run');
const btnReport = $('btn-report');
const pipelineStatus = $('pipeline-status');
const modalNew = $('modal-new');

// ── Init ───────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  loadFeatures();
  loadDecision();
  loadAllPhaseResults();  // preload so sidebar dots are colored on startup
  checkPipelineStatus();

  // Tab switching
  document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
  });

  btnRun.addEventListener('click', runPipeline);
  btnReport.addEventListener('click', generateReport);
  $('btn-new').addEventListener('click', () => modalNew.classList.remove('hidden'));
  $('btn-modal-cancel').addEventListener('click', () => modalNew.classList.add('hidden'));
  $('btn-modal-create').addEventListener('click', createFeature);
});

// ── Feature List ───────────────────────────────────────────────────────────
async function loadFeatures() {
  try {
    const res = await fetch('/api/features');
    state.features = await res.json();
    renderTree();
  } catch (e) {
    featureTree.innerHTML = '<div class="empty-state"><div class="big">⚠️</div>無法載入 Feature 清單</div>';
  }
}

function renderTree() {
  if (!state.features.length) {
    featureTree.innerHTML = '<div class="empty-state"><div class="big">📂</div>尚無 Feature 檔案</div>';
    return;
  }

  // Group by first path segment (phase dir)
  const groups = {};
  for (const f of state.features) {
    const parts = f.path.split('/');
    const group = parts.length > 1 ? parts[0] : '其他';
    (groups[group] = groups[group] || []).push(f);
  }

  let html = '';
  for (const [group, files] of Object.entries(groups)) {
    const phase = guessPhaseFromFiles(files);
    const isRunning = phase && !!state.phasePollers[phase];
    const phaseDot = isRunning ? 'running' : (phase ? getPhaseStatus(phase) : '');
    const btnIcon = isRunning ? '⏳' : '▶';
    const btnDisabled = isRunning ? 'disabled' : '';
    const phaseBtn = phase
      ? `<button class="btn-run-phase" data-phase="${phase}" ${btnDisabled} title="單獨執行 ${group}">${btnIcon}</button>`
      : '';
    html += `<div class="phase-group">
      <div class="phase-label">
        <div class="dot ${phaseDot}"></div>
        <span class="phase-name">${group}</span>
        ${phaseBtn}
      </div>`;
    for (const f of files) {
      const dotClass = getFeatureDotClass(f.path);
      const active = state.current === f.path ? ' active' : '';
      html += `<div class="feature-item${active}" data-path="${f.path}">
          <div class="dot ${dotClass}"></div>
          <span class="name" title="${f.path}">${f.name}</span>
        </div>`;
    }
    html += '</div>';
  }
  featureTree.innerHTML = html;

  document.querySelectorAll('.feature-item').forEach(el => {
    el.addEventListener('click', () => selectFeature(el.dataset.path));
  });
  document.querySelectorAll('.btn-run-phase').forEach(btn => {
    btn.addEventListener('click', e => { e.stopPropagation(); runPhase(parseInt(btn.dataset.phase)); });
  });
}

// Derive phase number from the feature files in a group
function guessPhaseFromFiles(files) {
  for (const f of files) {
    const p = guessPhase(f.path);
    if (p !== null) return p;
  }
  return null;
}

// Phase-level status: summary over all features in that phase
function getPhaseStatus(phase) {
  const data = state.results[phase];
  if (!data || !data.length) return '';
  const allPassed = data.every(f =>
    (f.elements || []).filter(e => e.type !== 'background').every(e =>
      (e.steps || []).every(s => s.result && s.result.status === 'passed')
    )
  );
  return allPassed ? 'passed' : 'failed';
}

function getFeatureDotClass(featurePath) {
  for (const phaseData of Object.values(state.results)) {
    for (const feature of phaseData) {
      // Match by feature URI containing the path
      if (feature.uri && feature.uri.includes(featurePath.replace(/^[^/]+\//, ''))) {
        const allPassed = feature.elements.every(e =>
          e.steps.every(s => s.result && s.result.status === 'passed')
        );
        return allPassed ? 'passed' : 'failed';
      }
    }
  }
  return '';
}

// ── Select Feature ─────────────────────────────────────────────────────────
async function selectFeature(path) {
  if (state.dirty && !confirm('有未儲存的變更，確定要離開嗎？')) return;
  state.current = path;
  state.dirty = false;
  renderTree();

  // Load feature content
  try {
    const res = await fetch(`/api/features/${encodeURIComponent(path)}`);
    const data = await res.json();
    renderEditor(path, data.content);
  } catch (e) {
    showEditorError('無法載入 Feature 內容');
  }

  // Load results for this feature's phase
  const phase = guessPhase(path);
  if (phase && !state.results[phase]) {
    await loadPhaseResults(phase);
  }
  renderResultsForFeature(path);
}

function guessPhase(path) {
  const m = path.match(/0*([1-4])_/);
  return m ? parseInt(m[1]) : null;
}

// ── Editor ─────────────────────────────────────────────────────────────────
function renderEditor(path, content) {
  panelEditor.innerHTML = `
    <div class="editor-toolbar">
      <span class="editor-path">${path}</span>
      <button id="btn-delete">🗑 刪除</button>
      <button id="btn-save">💾 儲存並推送</button>
    </div>
    <textarea id="editor-area" spellcheck="false">${escapeHtml(content)}</textarea>`;

  $('editor-area').addEventListener('input', () => {
    state.dirty = true;
    $('btn-save').textContent = '💾 儲存並推送 *';
  });
  $('btn-save').addEventListener('click', saveFeature);
  $('btn-delete').addEventListener('click', deleteFeature);
}

function showEditorError(msg) {
  panelEditor.innerHTML = `<div class="empty-state"><div class="big">⚠️</div>${msg}</div>`;
}

async function saveFeature() {
  const content = $('editor-area').value;
  const btn = $('btn-save');
  btn.disabled = true;
  btn.textContent = '推送中…';
  try {
    const res = await fetch(`/api/features/${encodeURIComponent(state.current)}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
    if (!res.ok) throw new Error(await res.text());
    state.dirty = false;
    btn.textContent = '✅ 已推送';
    setTimeout(() => { btn.textContent = '💾 儲存並推送'; btn.disabled = false; }, 2000);
  } catch (e) {
    btn.textContent = '❌ 失敗：' + e.message;
    btn.disabled = false;
  }
}

async function deleteFeature() {
  if (!confirm(`確定要刪除 ${state.current} 嗎？此操作將直接 push 到 GitHub。`)) return;
  try {
    await fetch(`/api/features/${encodeURIComponent(state.current)}`, { method: 'DELETE' });
    state.current = null;
    state.dirty = false;
    panelEditor.innerHTML = '<div class="empty-state"><div class="big">✏️</div>已刪除</div>';
    await loadFeatures();
  } catch (e) {
    alert('刪除失敗：' + e.message);
  }
}

// ── Create Feature ─────────────────────────────────────────────────────────
async function createFeature() {
  const path = $('modal-path').value.trim();
  if (!path || !path.endsWith('.feature')) {
    alert('請輸入有效路徑（以 .feature 結尾）');
    return;
  }
  try {
    await fetch(`/api/features/${encodeURIComponent(path)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    modalNew.classList.add('hidden');
    $('modal-path').value = '';
    await loadFeatures();
    selectFeature(path);
  } catch (e) {
    alert('建立失敗：' + e.message);
  }
}

// ── Results ────────────────────────────────────────────────────────────────
async function loadDecision() {
  try {
    const res = await fetch('/api/results');
    state.decision = await res.json();
  } catch (_) {}
}

async function loadPhaseResults(phase) {
  try {
    const res = await fetch(`/api/results/${phase}`);
    if (res.ok) state.results[phase] = await res.json();
  } catch (_) {}
}

async function loadAllPhaseResults() {
  await Promise.all([1, 2, 3, 4].map(p => loadPhaseResults(p)));
  renderTree();  // refresh dots after all results are loaded
}

function renderResultsForFeature(path) {
  const phase = guessPhase(path);
  const phaseData = phase ? state.results[phase] : null;

  let html = '';

  // Decision banner
  if (state.decision && state.decision.decision) {
    const isGo = state.decision.decision.includes('GO');
    const cls = state.decision.status === 'no_results' ? 'pending' : (isGo ? 'go' : 'nogo');
    html += `<div class="decision-banner ${cls}">
      決策：${state.decision.decision}
      &nbsp;&nbsp;通過率 ${state.decision.pass_rate ?? '—'}%
      （${state.decision.passed ?? '—'} / ${state.decision.total ?? '—'}）
    </div>`;
  } else {
    html += `<div class="decision-banner pending">尚無測試結果，請先執行 Pipeline</div>`;
  }

  if (!phaseData) {
    html += `<div class="empty-state"><div class="big">📊</div>Phase ${phase ?? '?'} 尚無結果</div>`;
    panelResults.innerHTML = html;
    return;
  }

  // Find matching feature
  const featureName = path.split('/').pop().replace('.feature', '');
  const matchedFeatures = phaseData.filter(f =>
    f.uri && (f.uri.includes(featureName) || f.name.includes(featureName))
  );
  const displayFeatures = matchedFeatures.length ? matchedFeatures : phaseData;

  for (const feature of displayFeatures) {
    html += `<div class="section-title">📋 ${feature.name}</div>`;
    for (const element of feature.elements || []) {
      if (element.type === 'background') continue;
      const passed = element.steps.every(s => s.result && s.result.status === 'passed');
      const totalNs = element.steps.reduce((sum, s) => sum + (s.result?.duration || 0), 0);
      const ms = (totalNs / 1e6).toFixed(0);
      const failedStep = element.steps.find(s => s.result && s.result.status !== 'passed');
      html += `
        <div class="scenario-card ${passed ? 'passed' : 'failed'}">
          <div class="icon">${passed ? '🟢' : '🔴'}</div>
          <div class="info">
            <div class="sname">${element.name}</div>
            ${failedStep ? `<div class="smeta">失敗步驟：${failedStep.name}</div>` : ''}
          </div>
          <div class="duration">${ms} ms</div>
        </div>`;
    }
  }

  panelResults.innerHTML = html;
}

// ── Individual Phase Execution ─────────────────────────────────────────────
async function runPhase(phaseNum) {
  try {
    const res = await fetch(`/api/run/phase/${phaseNum}`, { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || JSON.stringify(data));
    startPhasePolling(phaseNum);
  } catch (e) {
    alert(`Phase ${phaseNum} 執行失敗：${e.message}`);
  }
}

function startPhasePolling(phaseNum) {
  if (state.phasePollers[phaseNum]) return;
  renderTree();  // show spinner immediately
  state.phasePollers[phaseNum] = setInterval(async () => {
    try {
      const res = await fetch(`/api/run/phase/${phaseNum}/status`);
      const data = await res.json();
      const done = data.status !== 'Running' && data.status !== 'Pending' && data.status !== 'none';
      if (done) {
        clearInterval(state.phasePollers[phaseNum]);
        delete state.phasePollers[phaseNum];
        // Reload results for this phase only
        delete state.results[phaseNum];
        await loadPhaseResults(phaseNum);
        renderTree();
        if (state.current && guessPhase(state.current) === phaseNum) {
          renderResultsForFeature(state.current);
        }
      }
    } catch (_) {}
  }, 5000);
}

// ── Pipeline ───────────────────────────────────────────────────────────────
async function runPipeline() {
  if (!confirm('確定要觸發 Pre-SIT Pipeline 嗎？')) return;
  btnRun.disabled = true;
  btnRun.textContent = '⏳ 觸發中…';
  try {
    const res = await fetch('/api/run', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(JSON.stringify(data));
    startPolling();
  } catch (e) {
    alert('觸發失敗：' + e.message);
    btnRun.disabled = false;
    btnRun.textContent = '▶ Run Pipeline';
  }
}

async function checkPipelineStatus() {
  try {
    const res = await fetch('/api/run/status');
    const data = await res.json();
    updateStatusBadge(data);
    if (data.phase === 'Running') startPolling();
  } catch (_) {}
}

function startPolling() {
  if (state.pipelinePoller) return;
  state.pipelinePoller = setInterval(async () => {
    try {
      const res = await fetch('/api/run/status');
      const data = await res.json();
      updateStatusBadge(data);
      if (data.phase !== 'Running' && data.phase !== 'Pending') {
        clearInterval(state.pipelinePoller);
        state.pipelinePoller = null;
        btnRun.disabled = false;
        btnRun.textContent = '▶ Run Pipeline';
        // Refresh results
        await loadDecision();
        for (let p = 1; p <= 4; p++) await loadPhaseResults(p);
        if (state.current) renderResultsForFeature(state.current);
        renderTree();
      }
    } catch (_) {}
  }, 5000);
}

function updateStatusBadge(data) {
  const phase = data.phase || 'None';
  pipelineStatus.textContent = `Pipeline: ${phase}`;
  pipelineStatus.className = '';
  if (phase === 'Running' || phase === 'Pending') {
    pipelineStatus.classList.add('running');
    btnRun.disabled = true;
    btnRun.textContent = '⏳ 執行中…';
  } else if (phase === 'Succeeded') {
    pipelineStatus.classList.add('succeeded');
  } else if (phase === 'Failed' || phase === 'Error') {
    pipelineStatus.classList.add('failed');
  }
}

// ── Tab switching ──────────────────────────────────────────────────────────
function switchTab(tab) {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
  panelEditor.classList.toggle('active', tab === 'editor');
  panelResults.classList.toggle('active', tab === 'results');
  if (tab === 'results' && state.current) renderResultsForFeature(state.current);
}

// ── Report Generation ──────────────────────────────────────────────────────
async function generateReport() {
  btnReport.disabled = true;
  btnReport.textContent = '⏳ 產生中…';
  try {
    const res = await fetch('/api/report/generate', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(JSON.stringify(data));
    btnReport.textContent = '✅ 報告完成';
    // Open the report in a new tab
    window.open(data.url, '_blank');
    setTimeout(() => { btnReport.textContent = '📊 產生報告'; btnReport.disabled = false; }, 3000);
  } catch (e) {
    btnReport.textContent = '❌ 失敗';
    btnReport.disabled = false;
    alert('產生報告失敗：' + e.message);
  }
}

// ── Utils ──────────────────────────────────────────────────────────────────
function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
