/* UTNixOS_Pro 管理面板前端逻辑（原生 JS，无依赖） */
'use strict';

/* ---------- API 封装 ---------- */
async function api(path, opts = {}) {
  const init = { headers: {}, ...opts };
  if (opts.body && typeof opts.body === 'object') {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(opts.body);
  }
  const res = await fetch(path, init);
  let data = {};
  try { data = await res.json(); } catch (e) { /* 非 JSON 响应 */ }
  if (res.status === 401) {
    showLogin();
    throw new Error(data.error || '未登录');
  }
  if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status));
  return data;
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

/* ---------- 视图切换 ---------- */
const $ = id => document.getElementById(id);

function showLogin() {
  $('loginView').classList.remove('hidden');
  $('mainView').classList.add('hidden');
}

function showMain(user) {
  $('loginView').classList.add('hidden');
  $('mainView').classList.remove('hidden');
  $('whoami').textContent = user;
}

/* ---------- 登录 ---------- */
$('loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  $('loginError').classList.add('hidden');
  try {
    const data = await api('/api/login', {
      method: 'POST',
      body: { username: $('loginUser').value.trim(), password: $('loginPass').value }
    });
    showMain(data.user);
    initDashboard();
  } catch (err) {
    $('loginError').textContent = err.message;
    $('loginError').classList.remove('hidden');
  }
});

$('logoutBtn').addEventListener('click', async () => {
  try { await api('/api/logout', { method: 'POST' }); } catch (e) { /* 忽略 */ }
  showLogin();
});

/* ---------- 标签页 ---------- */
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    tab.classList.add('active');
    $('tab-' + tab.dataset.tab).classList.add('active');
    if (tab.dataset.tab === 'modules') loadModules();
    if (tab.dataset.tab === 'packages') loadPackages();
    if (tab.dataset.tab === 'rollback') loadGenerations();
    if (tab.dataset.tab === 'logs') loadLogUnits();
    if (tab.dataset.tab === 'audit') loadAudit();
  });
});

/* ---------- 初始化 ---------- */
async function initDashboard() {
  loadStatus();
  setInterval(() => { if (!document.hidden) loadStatus(); }, 30000);
}

/* ---------- 概览 ---------- */
async function loadStatus() {
  try {
    const st = await api('/api/status');
    const cards = [
      ['主机名', st.hostname], ['系统', st.os], ['当前 Generation', st.generation],
      ['运行时间', st.uptime], ['Nix 版本', st.nixVersion],
      ['配置目录', st.configDir + (st.hasFlake ? ' (flake)' : '')],
      ['磁盘', st.disk], ['/nix/store 大小', st.storeSize || '未知'],
    ];
    $('statusCards').innerHTML = '';
    cards.forEach(([k, v]) => {
      const c = el('div', 'card');
      c.append(el('div', 'k', k), el('div', 'v', v || '未知'));
      $('statusCards').append(c);
    });
  } catch (e) { /* 会话可能过期 */ }
}

/* ---------- 任务（op）执行 ---------- */
let currentOpStream = null;

async function startOp(type, extra = {}) {
  try {
    const op = await api('/api/ops', {
      method: 'POST',
      body: { type, ...extra }
    });
    openOpModal(op.id, op.type);
  } catch (err) {
    alert('无法启动任务：' + err.message);
  }
}

function openOpModal(id, type) {
  $('opTitle').textContent = '执行中：' + opTypeName(type);
  $('opConsole').innerHTML = '';
  $('opSummary').classList.add('hidden');
  $('opCloseBtn').classList.add('hidden');
  $('opCancelBtn').classList.remove('hidden');
  $('opModal').classList.remove('hidden');

  const es = new EventSource('/api/ops/' + id + '/stream');
  currentOpStream = es;
  es.onmessage = () => {};
  es.addEventListener('line', ev => appendConsole($('opConsole'), ev.data));
  es.addEventListener('status', ev => {
    const st = ev.data;
    const summary = $('opSummary');
    summary.textContent = '任务结束：' + (st === 'done' ? '✓ 完成' : st === 'cancelled' ? '已取消' : '✗ 失败');
    summary.classList.toggle('err', st === 'error' || st === 'cancelled');
    summary.classList.remove('hidden');
    $('opCancelBtn').classList.add('hidden');
    $('opCloseBtn').classList.remove('hidden');
    $('opBadge').classList.add('hidden');
  });
  es.addEventListener('summary', ev => {
    $('opSummary').textContent = ev.data;
  });
  es.onerror = () => {
    es.close();
    currentOpStream = null;
  };
  $('opBadge').textContent = '任务运行中';
  $('opBadge').classList.remove('hidden');
}

function opTypeName(t) {
  return { rebuild: '重建系统', update: '更新系统', gc: '清理垃圾',
    rollback: '系统回滚', 'temp-install': '临时安装', 'temp-remove': '临时卸载' }[t] || t;
}

function appendConsole(consoleEl, text) {
  const line = el('div', '', text);
  if (/error|失败|错误|✗/.test(text)) line.className = 'line-err';
  else if (/完成|✓|成功/.test(text)) line.className = 'line-ok';
  consoleEl.append(line);
  consoleEl.scrollTop = consoleEl.scrollHeight;
  // 同步到主控制台
  const main = $('console');
  if (main.firstChild && main.firstChild.className === 'console-empty') main.innerHTML = '';
  const mline = el('div', line.className, text);
  main.append(mline);
  while (main.childNodes.length > 2000) main.removeChild(main.firstChild);
  main.scrollTop = main.scrollHeight;
}

$('opCancelBtn').addEventListener('click', async () => {
  if (!currentOpStream) return;
  const id = currentOpStream.url.split('/').filter(Boolean).pop();
  try { await api('/api/ops/' + id + '/cancel', { method: 'POST' }); } catch (e) { /* 忽略 */ }
});

$('opCloseBtn').addEventListener('click', () => {
  $('opModal').classList.add('hidden');
  if (currentOpStream) { currentOpStream.close(); currentOpStream = null; }
  loadStatus();
  loadPackages();   // 重建/装包后刷新包列表
});

/* 概览操作按钮 */
document.querySelectorAll('.actions [data-op]').forEach(btn => {
  btn.addEventListener('click', () => {
    const type = btn.dataset.op;
    const extra = {};
    if (type === 'update') extra.mode = btn.dataset.mode;
    if (type === 'rebuild') {
      if (!confirm('确定要重建系统吗？（nixos-rebuild switch）')) return;
    }
    if (type === 'gc') {
      if (!confirm('确定要清理构建垃圾吗？（nix-collect-garbage -d，删除旧的 generations）')) return;
    }
    startOp(type, extra);
  });
});

/* ---------- 模块 ---------- */
let moduleOverview = null;

async function loadModules() {
  try {
    moduleOverview = await api('/api/modules');
    const wrap = $('moduleGroups');
    wrap.innerHTML = '';

    // 单选组（高亮 = 当前选中项）
    Object.values(moduleOverview.single).forEach(g => {
      const box = el('div', 'group');
      box.append(el('div', 'group-title', g.title + '（单选）'));
      const items = el('div', 'items');
      g.options.forEach(opt => {
        const isCurrent = opt.name === g.current;
        const chip = el('div', 'chip ' + (isCurrent ? 'on' : 'off'), opt.name);
        chip.addEventListener('click', () => selectSingle(g.key, opt.name));
        items.append(chip);
      });
      box.append(items);
      wrap.append(box);
    });

    // 多选组
    Object.values(moduleOverview.multi).forEach(g => {
      const box = el('div', 'group');
      box.append(el('div', 'group-title', g.title + '（多选）'));
      const items = el('div', 'items');
      g.options.forEach(m => {
        const chip = el('div', 'chip ' + (m.enabled ? 'on' : 'off'), m.name);
        chip.addEventListener('click', () => toggleMulti(g.key, m.name));
        items.append(chip);
      });
      box.append(items);
      wrap.append(box);
    });

    // 其他（只读）
    if (moduleOverview.other.length) {
      const box = el('div', 'group');
      box.append(el('div', 'group-title', '其他模块（只读展示，请手动编辑 configuration.nix）'));
      const items = el('div', 'items');
      moduleOverview.other.forEach(m => {
        items.append(el('div', 'chip disabled ' + (m.enabled ? 'on' : 'off'), m.name));
      });
      box.append(items);
      wrap.append(box);
    }
  } catch (e) { $('moduleNote').textContent = '加载失败：' + e.message; }
}

function selectSingle(key, name) {
  const g = moduleOverview.single[key];
  g.options.forEach(o => o.enabled = (o.name === name));
  g.current = name;
  loadModules(); // 重绘
}

function toggleMulti(key, name) {
  const g = moduleOverview.multi[key];
  g.options.forEach(o => { if (o.name === name) o.enabled = !o.enabled; });
  loadModules(); // 重绘
}

$('applyModulesBtn').addEventListener('click', async () => {
  if (!moduleOverview) return;
  const selection = {
    desktop: moduleOverview.single.desktop.current,
    boot: moduleOverview.single.boot.current,
    locale: moduleOverview.single.locale.current,
    input: moduleOverview.single.input.current,
    mirror: moduleOverview.single.mirrors.current,
    userShell: moduleOverview.single.shell.current,
    systemModules: moduleOverview.multi.system.options.filter(o => o.enabled).map(o => o.name),
    advanced: moduleOverview.multi.advanced.options.filter(o => o.enabled).map(o => o.name),
  };
  if (!confirm('应用这些模块选择并写入 configuration.nix？（可随后点「重建系统」生效）')) return;
  try {
    const res = await api('/api/modules/apply', { method: 'POST', body: { selection } });
    $('moduleNote').textContent = '✓ 已写入：' + res.changed.join('；') + '。点「重建系统」生效。';
    loadModules();
  } catch (e) { $('moduleNote').textContent = '✗ ' + e.message; }
});

/* ---------- 软件包 ---------- */
$('pkgSearchBtn').addEventListener('click', searchPackages);
$('pkgSearch').addEventListener('keydown', e => { if (e.key === 'Enter') searchPackages(); });

async function searchPackages() {
  const q = $('pkgSearch').value.trim();
  const box = $('pkgResults');
  if (!q) return;
  box.innerHTML = '<div class="empty">正在搜索 nixpkgs（首次可能较慢）...</div>';
  try {
    const res = await api('/api/packages/search?q=' + encodeURIComponent(q));
    box.innerHTML = '';
    if (!res.results.length) { box.append(el('div', 'empty', '没有找到匹配的包')); return; }
    res.results.forEach(p => {
      const item = el('div', 'pkg-item');
      const info = el('div');
      info.append(el('div', 'pkg-name', p.attr + (p.version ? '  ' + p.version : '')));
      if (p.description) info.append(el('div', 'pkg-desc', p.description));
      const acts = el('div', 'pkg-actions');
      const b1 = el('button', 'btn', '声明式安装');
      b1.addEventListener('click', () => declarativePkg(p.attr, false));
      const b2 = el('button', 'btn', '临时安装');
      b2.addEventListener('click', () => tempPkg(p.attr, false));
      acts.append(b1, b2);
      item.append(info, acts);
      box.append(item);
    });
  } catch (e) { box.innerHTML = ''; box.append(el('div', 'empty', '搜索失败：' + e.message)); }
}

async function declarativePkg(attr, remove) {
  try {
    const res = await api('/api/packages/declarative', {
      method: 'POST', body: { attr, remove }
    });
    $('pkgNote').textContent = '✓ ' + attr + (remove ? ' 已移除' : ' 已加入') + '（' + res.note + '）';
    loadPackages();
  } catch (e) { alert(e.message); }
}

async function tempPkg(attr, remove) {
  try {
    if (remove) {
      if (!confirm('临时卸载 ' + attr + '？')) return;
      await startOp('temp-remove', { attr });
    } else {
      await startOp('temp-install', { attr });
    }
  } catch (e) { alert(e.message); }
}

async function loadPackages() {
  try {
    const res = await api('/api/packages');
    const decl = $('declPkgs'), temp = $('tempPkgs');
    decl.innerHTML = ''; temp.innerHTML = '';
    if (!res.declarative.length) decl.append(el('div', 'empty', '暂无声明式安装的包'));
    res.declarative.forEach(a => {
      const item = el('div', 'pkg-item');
      item.append(el('div', 'pkg-name', a));
      const b = el('button', 'btn btn-danger', '移除');
      b.addEventListener('click', () => declarativePkg(a, true));
      const acts = el('div', 'pkg-actions'); acts.append(b);
      item.append(acts);
      decl.append(item);
    });
    if (!res.temp.length) temp.append(el('div', 'empty', '暂无临时安装的包（nix profile 安装，重建后失效）'));
    res.temp.forEach(p => {
      const item = el('div', 'pkg-item');
      item.append(el('div', 'pkg-name', p.name.replace('nixpkgs#', '')));
      const b = el('button', 'btn btn-danger', '卸载');
      b.addEventListener('click', () => tempPkg(p.name.replace('nixpkgs#', ''), true));
      const acts = el('div', 'pkg-actions'); acts.append(b);
      item.append(acts);
      temp.append(item);
    });
  } catch (e) { /* 忽略 */ }
}

/* ---------- 回滚 ---------- */
let selectedGen = null;

async function loadGenerations() {
  try {
    const res = await api('/api/generations');
    const body = $('gensBody');
    body.innerHTML = '';
    res.generations.forEach(g => {
      const tr = el('tr');
      if (g.current) tr.className = 'current';
      const radio = el('input');
      radio.type = 'radio';
      radio.name = 'gen';
      radio.checked = !!g.current;
      if (g.current) selectedGen = g.n;
      radio.addEventListener('change', () => selectedGen = g.n);
      const td1 = el('td'); td1.append(radio);
      tr.append(td1, el('td', '', 'Generation ' + g.n), el('td', '', g.date),
        el('td', '', g.current ? '● 当前' : ''));
      body.append(tr);
    });
    $('rollbackBtn').disabled = false;
  } catch (e) { /* 忽略 */ }
}

$('rollbackBtn').addEventListener('click', async () => {
  if (!selectedGen) return;
  if (!confirm('确定回滚到 Generation ' + selectedGen + ' 吗？\n（切换 profile 并立即激活，正在运行的服务可能重启）')) return;
  // 注意：回滚是独立端点 POST /api/rollback（/api/ops 不接受 type=rollback）
  try {
    const op = await api('/api/rollback', {
      method: 'POST',
      body: { generation: selectedGen }
    });
    openOpModal(op.id, op.type);
  } catch (err) {
    alert('无法启动回滚：' + err.message);
  }
});

/* ---------- 日志 ---------- */
let logStream = null;

async function loadLogUnits() {
  try {
    const res = await api('/api/logs/units');
    const sel = $('logUnit');
    const cur = sel.value;
    sel.innerHTML = '<option value="">全部服务</option>';
    res.units.forEach(u => {
      const o = el('option', '', u);
      o.value = u;
      sel.append(o);
    });
    sel.value = cur;
  } catch (e) { /* 忽略 */ }
}

$('logLoadBtn').addEventListener('click', loadLogs);

async function loadLogs() {
  stopLogStream();
  const unit = $('logUnit').value, lines = $('logLines').value || '200';
  $('logView').textContent = '加载中...';
  try {
    const res = await api('/api/logs?unit=' + encodeURIComponent(unit) + '&lines=' + lines);
    $('logView').textContent = res.output || '（无日志）';
    $('logView').scrollTop = $('logView').scrollHeight;
  } catch (e) { $('logView').textContent = '加载失败：' + e.message; }
}

function stopLogStream() {
  if (logStream) { logStream.close(); logStream = null; }
}

$('logFollowBtn').addEventListener('click', () => {
  stopLogStream();
  const unit = $('logUnit').value, lines = $('logLines').value || '100';
  $('logView').textContent = '实时跟踪中（journalctl -f）...';
  const es = new EventSource('/api/logs/stream?unit=' + encodeURIComponent(unit) + '&lines=' + lines);
  logStream = es;
  es.addEventListener('line', ev => {
    if ($('logView').textContent === '实时跟踪中（journalctl -f）...') $('logView').textContent = '';
    $('logView').textContent += ev.data + '\n';
    $('logView').scrollTop = $('logView').scrollHeight;
    // 防止过长
    if ($('logView').textContent.length > 200000) $('logView').textContent = $('logView').textContent.slice(-150000);
  });
  es.onerror = () => { es.close(); logStream = null; };
});

/* ---------- 审计 ---------- */
async function loadAudit() {
  try {
    const res = await api('/api/audit?limit=300');
    $('auditView').textContent = res.entries.length ? res.entries.join('\n') : '（暂无审计记录）';
    $('auditView').scrollTop = $('auditView').scrollHeight;
  } catch (e) { $('auditView').textContent = '加载失败：' + e.message; }
}

/* ---------- 启动 ---------- */
(async function boot() {
  try {
    const me = await api('/api/me');
    showMain(me.user);
    initDashboard();
  } catch (e) {
    showLogin();
  }
})();
