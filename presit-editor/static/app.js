// ── State ──────────────────────────────────────────────────────────────────
const state = {
  features: [],        // [{path, name}]
  results: {},         // {phase: [cucumber features]}
  decision: null,      // presit-decision.json
  current: null,       // currently selected feature path
  dirty: false,
  pipelinePoller: null,
  phasePollers: {},    // {phaseNum: intervalId}
  resetPoller: null,
};

// ── DOM refs ───────────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const featureTree = $('feature-tree');
const panelEditor = $('panel-editor');
const panelResults = $('panel-results');
const btnRun = $('btn-run');
const btnReport = $('btn-report');
const btnReset = $('btn-reset');
const pipelineStatus = $('pipeline-status');
const modalNew = $('modal-new');
const modalImport = $('modal-import');
const importFileInput = $('import-file-input');

// Pending import content while modal is open
let _importContent = '';

// ── Init ───────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  loadFeatures();
  loadDecision();
  loadAllPhaseResults();  // preload so sidebar dots are colored on startup
  checkPipelineStatus();
  checkResetStatus();

  // Tab switching
  document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
  });

  btnRun.addEventListener('click', runPipeline);
  btnReport.addEventListener('click', generateReport);
  btnReset.addEventListener('click', resetEnv);
  $('btn-new').addEventListener('click', () => modalNew.classList.remove('hidden'));
  $('btn-modal-cancel').addEventListener('click', () => modalNew.classList.add('hidden'));
  $('btn-modal-create').addEventListener('click', createFeature);
  $('btn-import').addEventListener('click', () => importFileInput.click());
  importFileInput.addEventListener('change', onImportFileSelected);
  $('btn-import-cancel').addEventListener('click', () => { modalImport.classList.add('hidden'); _importContent = ''; });
  $('btn-import-confirm').addEventListener('click', confirmImport);
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

  const pipelineRunning = !!state.pipelinePoller;
  const resetting = !!state.resetPoller;
  let html = '';
  for (const [group, files] of Object.entries(groups)) {
    const phase = guessPhaseFromFiles(files);
    const phasePolling = phase && !!state.phasePollers[phase];
    const phaseDot = phasePolling ? 'running' : (phase ? getPhaseStatus(phase) : '');
    const btnIcon = phasePolling ? '⏳ 執行中' : '▶ 執行';
    const btnDisabled = (phasePolling || pipelineRunning || resetting) ? 'disabled' : '';
    const phaseBtn = phase
      ? `<button class="btn-run-phase" data-phase="${phase}" ${btnDisabled}>${btnIcon}</button>`
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
  const tail = featurePath.includes('/') ? featurePath.replace(/^[^/]+\//, '') : featurePath;
  for (const phaseData of Object.values(state.results)) {
    for (const feature of phaseData) {
      if (feature.uri && feature.uri.includes(tail)) {
        const scenarios = (feature.elements || []).filter(e => e.type !== 'background');
        if (!scenarios.length) return '';
        const allPassed = scenarios.every(e =>
          (e.steps || []).every(s => s.result && s.result.status === 'passed')
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
  // file prefix: 01_xxx, 02_xxx (most common pattern in this project)
  let m = path.match(/(?:^|\/)0*([1-4])_/);
  if (m) return parseInt(m[1]);
  // directory name: phase-1/, phase_1/, phase1/
  m = path.match(/phase[-_]?([1-4])\//i);
  if (m) return parseInt(m[1]);
  return null;
}

// ── Editor ─────────────────────────────────────────────────────────────────
function renderEditor(path, content) {
  panelEditor.innerHTML = `
    <div class="editor-toolbar">
      <span class="editor-path">${path}</span>
      <button id="btn-export">⬇ 匯出</button>
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
  $('btn-export').addEventListener('click', exportFeature);
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
  state.phasePollers[phaseNum] = -1;  // sentinel: gray out immediately before fetch
  renderTree();
  syncRunButton();
  try {
    const res = await fetch(`/api/run/phase/${phaseNum}`, { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || JSON.stringify(data));
    startPhasePolling(phaseNum);
  } catch (e) {
    delete state.phasePollers[phaseNum];
    renderTree();
    syncRunButton();
    alert(`Phase ${phaseNum} 執行失敗：${e.message}`);
  }
}

function startPhasePolling(phaseNum) {
  if (state.phasePollers[phaseNum] > 0) return;  // real interval already running (not sentinel -1)
  renderTree();
  state.phasePollers[phaseNum] = setInterval(async () => {
    try {
      const res = await fetch(`/api/run/phase/${phaseNum}/status`);
      const data = await res.json();
      const done = data.status !== 'Running' && data.status !== 'Pending' && data.status !== 'none';
      if (done) {
        clearInterval(state.phasePollers[phaseNum]);
        delete state.phasePollers[phaseNum];
        delete state.results[phaseNum];
        await loadPhaseResults(phaseNum);
        renderTree();
        syncRunButton();
        if (state.current && guessPhase(state.current) === phaseNum) {
          renderResultsForFeature(state.current);
        }
      }
    } catch (_) {}
  }, 5000);
}

// ── Pipeline ───────────────────────────────────────────────────────────────
async function runPipeline() {
  btnRun.disabled = true;
  btnRun.textContent = '⏳ 觸發中…';
  try {
    const res = await fetch('/api/run', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(JSON.stringify(data));
    startPolling();
  } catch (e) {
    alert('觸發失敗：' + e.message);
    syncRunButton();
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
        syncRunButton();
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

function syncRunButton() {
  const anyPhaseRunning = Object.keys(state.phasePollers).length > 0;
  const blocked = anyPhaseRunning || !!state.pipelinePoller || !!state.resetPoller;
  if (blocked) {
    btnRun.disabled = true;
    if (!state.pipelinePoller && !state.resetPoller) btnRun.textContent = '⏳ 執行中…';
  } else {
    btnRun.disabled = false;
    btnRun.textContent = '▶ Run Pipeline';
  }
}

// ── Tab switching ──────────────────────────────────────────────────────────
function switchTab(tab) {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
  panelEditor.classList.toggle('active', tab === 'editor');
  panelResults.classList.toggle('active', tab === 'results');
  if (tab === 'results' && state.current) renderResultsForFeature(state.current);
}

// ── Export ────────────────────────────────────────────────────────────────
function exportFeature() {
  const content = $('editor-area').value;
  const filename = state.current.split('/').pop();  // keep the original .feature filename
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ── Import ────────────────────────────────────────────────────────────────
function onImportFileSelected(e) {
  const file = e.target.files[0];
  e.target.value = '';  // reset so same file can be re-selected
  if (!file) return;
  if (!file.name.endsWith('.feature')) {
    alert('請選擇副檔名為 .feature 的檔案');
    return;
  }
  const reader = new FileReader();
  reader.onload = ev => {
    _importContent = ev.target.result;
    $('import-path').value = file.name;
    modalImport.classList.remove('hidden');
    $('import-path').focus();
    $('import-path').select();
  };
  reader.readAsText(file, 'utf-8');
}

async function confirmImport() {
  const path = $('import-path').value.trim();
  if (!path || !path.endsWith('.feature')) {
    alert('路徑必須以 .feature 結尾');
    return;
  }
  const exists = state.features.some(f => f.path === path);
  if (exists && !confirm(`「${path}」已存在，確定要覆蓋並推送嗎？`)) return;

  const btn = $('btn-import-confirm');
  btn.disabled = true;
  btn.textContent = '匯入中…';
  try {
    const method = exists ? 'PUT' : 'POST';
    const res = await fetch(`/api/features/${encodeURIComponent(path)}`, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: _importContent }),
    });
    if (!res.ok) throw new Error(await res.text());
    modalImport.classList.add('hidden');
    _importContent = '';
    await loadFeatures();
    await selectFeature(path);
  } catch (err) {
    alert('匯入失敗：' + err.message);
  } finally {
    btn.disabled = false;
    btn.textContent = '確認匯入';
  }
}

// ── Environment Reset ─────────────────────────────────────────────────────────
async function resetEnv() {
  if (!confirm('確定清除所有測試結果並重置資料庫？\n\n此操作將：\n• 刪除全部 BDD 測試 Jobs\n• 清除 cucumber 報告\n• 重啟 Postgres（emptyDir 清空，Flyway 重建測試資料）\n• 重啟 PetClinic 服務')) return;
  btnReset.disabled = true;
  btnReset.textContent = '⏳ 重置中…';
  btnRun.disabled = true;
  state.results = {};
  state.decision = null;
  renderTree();
  try {
    const res = await fetch('/api/reset', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || JSON.stringify(data));
    startResetPolling();
  } catch (e) {
    alert('重置失敗：' + e.message);
    btnReset.disabled = false;
    btnReset.textContent = '🔄 清除重置';
    syncRunButton();
  }
}

function startResetPolling() {
  if (state.resetPoller) return;
  state.resetPoller = setInterval(async () => {
    try {
      const res = await fetch('/api/reset/status');
      const data = await res.json();
      const done = data.status !== 'Running' && data.status !== 'Pending' && data.status !== 'none';
      if (done) {
        clearInterval(state.resetPoller);
        state.resetPoller = null;
        if (data.status === 'Succeeded') {
          btnReset.textContent = '✅ 重置完成';
          setTimeout(() => { btnReset.textContent = '🔄 清除重置'; btnReset.disabled = false; }, 3000);
        } else {
          btnReset.textContent = '❌ 重置失敗';
          alert('環境重置失敗，請確認 K8s 狀態');
          setTimeout(() => { btnReset.textContent = '🔄 清除重置'; btnReset.disabled = false; }, 3000);
        }
        syncRunButton();
        renderTree();
      }
    } catch (_) {}
  }, 5000);
}

async function checkResetStatus() {
  try {
    const res = await fetch('/api/reset/status');
    const data = await res.json();
    if (data.status === 'Running' || data.status === 'Pending') {
      btnReset.disabled = true;
      btnReset.textContent = '⏳ 重置中…';
      startResetPolling();
    }
  } catch (_) {}
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
