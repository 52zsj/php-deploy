const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const els = {
  configSelect: $("#configSelect"),
  demoBtn: $("#demoBtn"),
  configName: $("#configName"),
  runGroup: $("#runGroup"),
  repoUrl: $("#repoUrl"),
  defaultBranch: $("#defaultBranch"),
  localDir: $("#localDir"),
  gitSshKey: $("#gitSshKey"),
  gitUsername: $("#gitUsername"),
  gitPassword: $("#gitPassword"),
  gitSshField: $("#gitSshField"),
  gitPasswordFields: $("#gitPasswordFields"),
  rsyncOptions: $("#rsyncOptions"),
  excludeList: $("#excludeList"),
  replaceDir: $("#replaceDir"),
  defaultPostSync: $("#defaultPostSync"),
  groupsContainer: $("#groupsContainer"),
  addGroupBtn: $("#addGroupBtn"),
  saveBtn: $("#saveBtn"),
  runBtn: $("#runBtn"),
  optVerbose: $("#optVerbose"),
  optForce: $("#optForce"),
  postSyncMode: $("#postSyncMode"),
  postSyncPicker: $("#postSyncPicker"),
  postSyncList: $("#postSyncList"),
  postSyncSelectAll: $("#postSyncSelectAll"),
  saveStatus: $("#saveStatus"),
  output: $("#output"),
  runStatus: $("#runStatus"),
  clearOutputBtn: $("#clearOutputBtn"),
  scrollBottomBtn: $("#scrollBottomBtn"),
  replaceDirView: $("#replaceDirView"),
  replaceEnvLabel: $("#replaceEnvLabel"),
  replacePrefix: $("#replacePrefix"),
  replaceStripTop: $("#replaceStripTop"),
  replaceRefreshBtn: $("#replaceRefreshBtn"),
  replaceUploadFilesBtn: $("#replaceUploadFilesBtn"),
  replaceUploadDirBtn: $("#replaceUploadDirBtn"),
  replaceUploadArchiveBtn: $("#replaceUploadArchiveBtn"),
  replaceUploadFiles: $("#replaceUploadFiles"),
  replaceUploadDir: $("#replaceUploadDir"),
  replaceUploadArchive: $("#replaceUploadArchive"),
  replaceSaveFileBtn: $("#replaceSaveFileBtn"),
  replaceSelectAllBtn: $("#replaceSelectAllBtn"),
  replaceDeleteSelectedBtn: $("#replaceDeleteSelectedBtn"),
  replaceFileList: $("#replaceFileList"),
  replaceFilePath: $("#replaceFilePath"),
  replaceFileContent: $("#replaceFileContent"),
  replaceFileStatus: $("#replaceFileStatus"),
  tabConfig: $("#tabConfig"),
  tabReplace: $("#tabReplace"),
};

/** 当前 env 下的扁平文件列表缓存，供树勾选展开 */
let replaceFilesCache = [];

let running = false;
let stickToBottom = true;
/** 上次由配置名自动推导时的基名，用于判断 local_dir / replace_dir 是否仍是自动值 */
let lastAutoName = "";

function configBaseName() {
  return els.configName.value.trim().replace(/\.yml$/i, "");
}

function defaultReplaceDir(name) {
  const n = (name || configBaseName()).trim();
  return n ? `./replace/${n}` : "";
}

function defaultLocalDir(name) {
  const n = (name || configBaseName()).trim();
  return n ? `/tmp/${n}` : "";
}

/** 旧约定 ~/replace/xxx → 项目相对 ./replace/<配置名> */
function isHomeStyleReplaceDir(val) {
  const v = (val || "").trim();
  return !v || /^~\/replace\//i.test(v) || /^~\\replace\\/i.test(v);
}

function normalizeReplaceDir(val, name) {
  const v = (val || "").trim();
  if (isHomeStyleReplaceDir(v)) return defaultReplaceDir(name);
  return v;
}

/** 保存时：空或 ~/replace 旧路径 → ./replace/<配置名> */
function ensureReplaceDirOnSave() {
  els.replaceDir.value = normalizeReplaceDir(els.replaceDir.value, configBaseName());
}

function effectiveReplaceDir() {
  return els.replaceDir.value.trim() || defaultReplaceDir();
}

function currentDeployEnv() {
  const groupIdx = Math.max(0, parseInt(els.runGroup.value || "1", 10) - 1);
  const card = $$(".group-card", els.groupsContainer)[groupIdx];
  if (!card) return "";
  return $(".group-env", card)?.value.trim() || "";
}

/** 配置名变化时，仅当 local_dir / replace_dir 为空或仍是上一轮自动值时才覆盖 */
function onConfigNameChange() {
  const name = configBaseName();
  if (!name) return;
  const prevLocal = lastAutoName ? `/tmp/${lastAutoName}` : "";
  const prevReplace = lastAutoName ? `./replace/${lastAutoName}` : "";
  const prevHomeReplace = lastAutoName ? `~/replace/${lastAutoName}` : "";
  if (!els.localDir.value.trim() || els.localDir.value.trim() === prevLocal) {
    els.localDir.value = defaultLocalDir(name);
  }
  const curReplace = els.replaceDir.value.trim();
  if (
    !curReplace ||
    curReplace === prevReplace ||
    curReplace === prevHomeReplace ||
    isHomeStyleReplaceDir(curReplace)
  ) {
    els.replaceDir.value = defaultReplaceDir(name);
  }
  lastAutoName = name;
  syncReplaceContext();
}

function setSaveStatus(text, type = "") {
  els.saveStatus.textContent = text;
  els.saveStatus.className = "status-badge";
  if (type) els.saveStatus.classList.add(type);
}

function linesToList(text) {
  return text
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
}

function listToLines(arr) {
  return (arr || []).join("\n");
}

function configFileName() {
  const name = els.configName.value.trim();
  if (!name) return "";
  return name.endsWith(".yml") ? name : `${name}.yml`;
}

function setGitAuthUI(type) {
  const isSsh = type === "ssh";
  els.gitSshField.classList.toggle("hidden", !isSsh);
  els.gitPasswordFields.classList.toggle("hidden", isSsh);
}

function bindGitAuthRadios() {
  $$('input[name="gitAuth"]').forEach((radio) => {
    radio.addEventListener("change", () => setGitAuthUI(radio.value));
  });
  setGitAuthUI($('input[name="gitAuth"]:checked')?.value || "ssh");
}

function syncServerAuthInfoType(card) {
  const auth = $(".server-auth-type:checked", card)?.value || "ssh";
  const input = $(".server-auth-info", card);
  const hint = $(".server-auth-hint", card);
  if (!input) return;
  input.type = "text";
  input.autocomplete = "off";
  input.spellcheck = false;
  if (auth === "password") {
    input.placeholder = "新密码（留空不改）";
    if (hint) {
      const saved = card.dataset.authSaved === "1";
      hint.classList.toggle("hidden", !saved);
    }
  } else {
    input.placeholder = "~/.ssh/id_rsa";
    if (hint) hint.classList.add("hidden");
  }
}

const DEFAULT_TARGET_DIR = "/www/wwwroot";
const DEFAULT_POST_SYNC = ["chown -R www:www {target_dir}"];

function isBlankObject(data) {
  return !data || (typeof data === "object" && !Array.isArray(data) && Object.keys(data).length === 0);
}

function readServerCard(node) {
  const authType = $(".server-auth-type:checked", node)?.value || "ssh";
  return {
    name: $(".server-name", node).value.trim(),
    host: $(".server-host", node).value.trim(),
    target_dir: $(".server-target", node).value.trim() || DEFAULT_TARGET_DIR,
    branch: $(".server-branch", node).value.trim(),
    auth_type: authType,
    auth_info: authType === "ssh" ? $(".server-auth-info", node).value.trim() : "",
    _auth_info_saved: authType === "password" && node.dataset.authSaved === "1",
    post_sync_commands: linesToList($(".server-post-sync", node).value),
  };
}

function readGroupCard(node) {
  return {
    name: $(".group-name", node).value.trim(),
    env: $(".group-env", node).value.trim(),
    post_sync_commands: linesToList($(".group-post-sync", node).value),
    servers: $$(".server-card", node).map((s) => readServerCard(s)),
  };
}

function createServerCard(data = {}) {
  if (isBlankObject(data)) {
    data = {
      target_dir: DEFAULT_TARGET_DIR,
      post_sync_commands: DEFAULT_POST_SYNC.slice(),
    };
  }
  const tpl = $("#serverTemplate");
  const node = tpl.content.firstElementChild.cloneNode(true);
  const uid = `srv_${Math.random().toString(36).slice(2, 8)}`;
  $$(".server-auth-type", node).forEach((r) => (r.name = uid));

  $(".server-name", node).value = data.name || "";
  $(".server-host", node).value = data.host || "";
  $(".server-target", node).value = data.target_dir || DEFAULT_TARGET_DIR;
  $(".server-branch", node).value = data.branch || els.defaultBranch.value || "master";
  const authType = data.auth_type || "ssh";
  $(`.server-auth-type[value="${authType}"]`, node).checked = true;
  if (authType === "password") {
    $(".server-auth-info", node).value = "";
    node.dataset.authSaved = data._auth_info_saved ? "1" : "0";
  } else {
    $(".server-auth-info", node).value = data.auth_info || "";
    node.dataset.authSaved = "0";
  }
  $(".server-post-sync", node).value = listToLines(
    data.post_sync_commands?.length ? data.post_sync_commands : []
  );

  $$(".server-auth-type", node).forEach((r) => {
    r.addEventListener("change", () => syncServerAuthInfoType(node));
  });
  syncServerAuthInfoType(node);

  $(".remove-server", node).addEventListener("click", () => node.remove());
  return node;
}

function createGroupCard(data = {}) {
  if (isBlankObject(data)) {
    data = {
      post_sync_commands: DEFAULT_POST_SYNC.slice(),
      servers: [{}],
    };
  }
  const tpl = $("#groupTemplate");
  const node = tpl.content.firstElementChild.cloneNode(true);
  $(".group-name", node).value = data.name || "";
  $(".group-env", node).value = data.env || "";
  $(".group-post-sync", node).value = listToLines(data.post_sync_commands);

  const serversBox = $(".servers-container", node);
  const servers = data.servers?.length ? data.servers : [{}];
  servers.forEach((s) => serversBox.appendChild(createServerCard(s)));

  $(".add-server", node).addEventListener("click", () => {
    const cards = $$(".server-card", serversBox);
    let next = {};
    if (cards.length) {
      next = readServerCard(cards[cards.length - 1]);
      if (next.name) next.name = `${next.name}-副本`;
      // 密码不回填明文；若上一节点已保存密钥，标记需用户确认或重填
      if (next.auth_type === "password") {
        next.auth_info = "";
        next._auth_info_saved = false;
      }
    }
    serversBox.appendChild(createServerCard(next));
  });
  $(".remove-group", node).addEventListener("click", () => {
    node.remove();
    refreshRunGroupOptions();
  });

  return node;
}

function refreshRunGroupOptions() {
  const prev = els.runGroup.value;
  els.runGroup.innerHTML = "";
  $$(".group-card", els.groupsContainer).forEach((card, idx) => {
    const name = $(".group-name", card).value || `组 ${idx + 1}`;
    const opt = document.createElement("option");
    opt.value = String(idx + 1);
    opt.textContent = `[${idx + 1}] ${name}`;
    els.runGroup.appendChild(opt);
  });
  if (prev) els.runGroup.value = prev;
  refreshPostSyncPicker();
}

/** 解析当前部署组生效的同步后命令（节点 > 组 > 全局，取第一层非空） */
function resolvePostSyncCommands() {
  const groupIdx = Math.max(0, parseInt(els.runGroup.value || "1", 10) - 1);
  const cards = $$(".group-card", els.groupsContainer);
  const card = cards[groupIdx];
  const globalCmds = linesToList(els.defaultPostSync.value);

  if (!card) {
    return { source: "全局默认", commands: globalCmds };
  }

  const servers = $$(".server-card", card);
  // 若任一节点有自己的命令，用第一个有命令的节点（与 sync 按节点执行一致时的展示用并集提示）
  for (const srv of servers) {
    const cmds = linesToList($(".server-post-sync", srv).value);
    if (cmds.length) {
      const name = $(".server-name", srv).value || "节点";
      return { source: `服务器级别 (${name})`, commands: cmds };
    }
  }

  const groupCmds = linesToList($(".group-post-sync", card).value);
  if (groupCmds.length) {
    return { source: "服务器组级别", commands: groupCmds };
  }

  return { source: "全局默认", commands: globalCmds };
}

function refreshPostSyncPicker() {
  const mode = els.postSyncMode.value;
  els.postSyncPicker.classList.toggle("hidden", mode !== "pick");
  if (mode !== "pick") return;

  const { source, commands } = resolvePostSyncCommands();
  els.postSyncList.innerHTML = "";

  if (!commands.length) {
    els.postSyncList.innerHTML = `<div class="picker-empty">当前组无同步后命令（来源: ${source}）</div>`;
    return;
  }

  const head = document.createElement("div");
  head.className = "picker-empty";
  head.textContent = `来源: ${source}`;
  els.postSyncList.appendChild(head);

  commands.forEach((cmd, idx) => {
    const label = document.createElement("label");
    label.innerHTML = `<input type="checkbox" class="post-cmd-check" checked data-idx="${idx}"><span></span>`;
    $("span", label).textContent = cmd;
    label.dataset.cmd = cmd;
    els.postSyncList.appendChild(label);
  });
}

function getSelectedPostCommands() {
  return $$(".post-cmd-check:checked", els.postSyncList).map((input) => {
    return input.closest("label").dataset.cmd;
  });
}

function addGroup(data) {
  // 无参数点击「添加组」时，复制上一组
  if (isBlankObject(data)) {
    const cards = $$(".group-card", els.groupsContainer);
    if (cards.length) {
      data = readGroupCard(cards[cards.length - 1]);
      if (data.name) data.name = `${data.name}-副本`;
      if (data.env) data.env = `${data.env}_copy`;
      (data.servers || []).forEach((s) => {
        if (s.name) s.name = `${s.name}-副本`;
        if (s.auth_type === "password") {
          s.auth_info = "";
          s._auth_info_saved = false;
        }
      });
    }
  }
  const card = createGroupCard(data);
  els.groupsContainer.appendChild(card);
  $$("input", card).forEach((input) => input.addEventListener("input", refreshRunGroupOptions));
  refreshRunGroupOptions();
}

function collectForm() {
  const gitAuth = $('input[name="gitAuth"]:checked')?.value || "ssh";
  const gitee = {
    repo_url: els.repoUrl.value.trim(),
    default_branch: els.defaultBranch.value.trim() || "master",
    local_dir: els.localDir.value.trim(),
    auth_type: gitAuth,
  };
  if (gitAuth === "ssh") {
    gitee.ssh_key = els.gitSshKey.value.trim();
  } else {
    gitee.username = els.gitUsername.value.trim();
    gitee.password = els.gitPassword.value.trim();
  }

  const server_groups = $$(".group-card", els.groupsContainer).map((card) => {
    const group = {
      name: $(".group-name", card).value.trim(),
      env: $(".group-env", card).value.trim(),
      servers: $$(".server-card", card).map((srv) => {
        const server = {
          name: $(".server-name", srv).value.trim(),
          host: $(".server-host", srv).value.trim(),
          target_dir: $(".server-target", srv).value.trim(),
          branch: $(".server-branch", srv).value.trim() || gitee.default_branch,
          auth_type: $('.server-auth-type:checked', srv)?.value || "ssh",
          auth_info: $(".server-auth-info", srv).value.trim(),
        };
        const post = linesToList($(".server-post-sync", srv).value);
        if (post.length) server.post_sync_commands = post;
        return server;
      }),
    };
    const groupPost = linesToList($(".group-post-sync", card).value);
    if (groupPost.length) group.post_sync_commands = groupPost;
    return group;
  });

  ensureReplaceDirOnSave();

  const raw = {
    gitee,
    sync: {
      rsync_options: els.rsyncOptions.value.trim() || "-az --progress",
      exclude: linesToList(els.excludeList.value),
      replace_dir: els.replaceDir.value.trim() || defaultReplaceDir(),
    },
    server_groups,
  };

  const defaultPost = linesToList(els.defaultPostSync.value);
  if (defaultPost.length) raw.default_post_sync_commands = defaultPost;

  return {
    config_name: els.configName.value.trim(),
    raw,
  };
}

function fillForm(payload) {
  const raw = payload.raw || payload;
  els.configName.value = payload.config_name || "";
  lastAutoName = configBaseName();
  els.repoUrl.value = raw.gitee?.repo_url || "";
  els.defaultBranch.value = raw.gitee?.default_branch || "develop";
  els.localDir.value = raw.gitee?.local_dir || defaultLocalDir();
  const auth = raw.gitee?.auth_type || "ssh";
  $(`input[name="gitAuth"][value="${auth}"]`).checked = true;
  setGitAuthUI(auth);
  els.gitSshKey.value = raw.gitee?.ssh_key || "~/.ssh/id_rsa";
  els.gitUsername.value = raw.gitee?.username || "";
  els.gitPassword.value = "";
  const gitHint = $("#gitPasswordHint");
  if (gitHint) {
    gitHint.classList.toggle("hidden", !(auth === "password" && raw.gitee?._password_saved));
  }

  els.rsyncOptions.value = raw.sync?.rsync_options || "-az --progress";
  els.excludeList.value = listToLines(raw.sync?.exclude);
  els.replaceDir.value = normalizeReplaceDir(raw.sync?.replace_dir, configBaseName());
  els.defaultPostSync.value = listToLines(raw.default_post_sync_commands);

  els.groupsContainer.innerHTML = "";
  (raw.server_groups || [{}]).forEach((g) => addGroup(g));
  refreshPostSyncPicker();
  syncReplaceContext();
}

async function fetchConfigs() {
  const res = await fetch("/api/configs");
  const data = await res.json();
  els.configSelect.innerHTML = '<option value="">选择配置…</option>';
  data.configs.forEach((name) => {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    els.configSelect.appendChild(opt);
  });
}

async function loadConfig(name) {
  if (!name) return;
  const res = await fetch(`/api/config?name=${encodeURIComponent(name)}`);
  if (!res.ok) throw new Error("加载失败");
  const data = await res.json();
  fillForm(data);
  setSaveStatus(`已加载 ${name}`, "ok");
}

async function saveConfig() {
  const body = collectForm();
  if (!body.config_name) throw new Error("请填写配置文件名");
  if (!body.raw.gitee.repo_url || !body.raw.gitee.local_dir) {
    throw new Error("请填写仓库 URL 和本地目录");
  }
  if (!body.raw.server_groups.length) throw new Error("至少添加一个服务器组");

  const res = await fetch("/api/config", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "保存失败");
  await fetchConfigs();
  els.configSelect.value = data.name;
  // 保存后清空密码框，不再展示
  els.gitPassword.value = "";
  $$(".server-card").forEach((card) => {
    const auth = $(".server-auth-type:checked", card)?.value;
    if (auth === "password") {
      $(".server-auth-info", card).value = "";
      card.dataset.authSaved = "1";
      syncServerAuthInfoType(card);
    }
  });
  const gitHint = $("#gitPasswordHint");
  if (gitHint && $('input[name="gitAuth"]:checked')?.value === "password") {
    gitHint.classList.remove("hidden");
  }
  setSaveStatus(`已保存 ${data.name}（密码已写入 .secrets）`, "ok");
  return data.name;
}

function clearOutput() {
  els.output.innerHTML = "";
}

function scrollOutputToBottom(force = false) {
  if (!force && !stickToBottom) return;
  requestAnimationFrame(() => {
    els.output.scrollTop = els.output.scrollHeight;
  });
}

function updateScrollBottomBtn() {
  const el = els.output;
  const gap = el.scrollHeight - el.scrollTop - el.clientHeight;
  const atBottom = gap < 48;
  stickToBottom = atBottom;
  els.scrollBottomBtn.classList.toggle("hidden", atBottom);
}

const BOX_LINE_RE = /^[\s╔╗╚╝║═╠╣╬┼─│]+$/;
const GITSHIP_LINE_RE = /GitShip\s+v?[\d.]+/i;
const SEPARATOR_LINE_RE = /^[─\-_=]{8,}$/;
const FINAL_SYNC_DONE_RE = /^✓\s*同步完成\.?$/;

function appendBanner(versionRaw) {
  const ver = String(versionRaw || "").replace(/^GitShip\s*/i, "").trim();
  let el = els.output.querySelector(".log-banner[data-run-banner]");
  if (!el) {
    el = document.createElement("div");
    el.className = "log-banner";
    el.dataset.runBanner = "1";
    el.innerHTML = `<span class="log-banner-mark">G</span><span class="log-banner-text"><strong>GitShip</strong><span class="log-banner-ver"></span></span>`;
    els.output.appendChild(el);
  }
  const verEl = el.querySelector(".log-banner-ver");
  if (verEl) verEl.textContent = ver ? `v${ver.replace(/^v/i, "")}` : "";
  scrollOutputToBottom();
}

function upsertSuccessCard(title = "同步完成", detail = "") {
  let el = els.output.querySelector(".log-success[data-run-success]");
  if (!el) {
    el = document.createElement("div");
    el.className = "log-success";
    el.dataset.runSuccess = "1";
    el.innerHTML = `<span class="log-success-icon">✓</span><span><div class="log-success-title"></div><div class="log-success-detail hidden"></div></span>`;
    els.output.appendChild(el);
  }
  const titleEl = el.querySelector(".log-success-title");
  const detailEl = el.querySelector(".log-success-detail");
  if (titleEl) titleEl.textContent = title;
  if (detailEl) {
    if (detail) {
      detailEl.textContent = detail;
      detailEl.classList.remove("hidden");
    }
  }
  scrollOutputToBottom();
}

function appendOutput(text, level = "info", replaceKey = "") {
  const placeholder = $(".output-placeholder", els.output);
  if (placeholder) placeholder.remove();

  const trimmed = String(text || "").trim();
  if (!trimmed) return;

  // 旧版 ASCII 框线 / 分隔线：静默跳过
  if (BOX_LINE_RE.test(trimmed) || SEPARATOR_LINE_RE.test(trimmed)) {
    const ship = trimmed.match(GITSHIP_LINE_RE);
    if (ship) appendBanner(ship[0]);
    return;
  }

  if (GITSHIP_LINE_RE.test(trimmed) && trimmed.length < 32) {
    appendBanner(trimmed);
    return;
  }

  // 中间步骤的「所有服务器同步完成」不重复展示
  if (/所有服务器同步完成/.test(trimmed)) {
    return;
  }

  if (FINAL_SYNC_DONE_RE.test(trimmed)) {
    upsertSuccessCard("同步完成");
    return;
  }

  if (/^日志\s/.test(trimmed) || trimmed.startsWith("详细日志:")) {
    const detail = trimmed.replace(/^(日志|详细日志:)\s*/, "");
    upsertSuccessCard("同步完成", detail);
    return;
  }

  if (replaceKey) {
    let line = els.output.querySelector(`[data-replace="${replaceKey}"]`);
    if (!line) {
      line = document.createElement("div");
      line.dataset.replace = replaceKey;
      els.output.appendChild(line);
    }
    line.className = `line-${level}`;
    if (line.textContent !== trimmed) {
      line.textContent = trimmed;
    }
  } else if (level === "meta") {
    const line = document.createElement("div");
    line.className = "line-meta";
    line.textContent = `$ ${trimmed}`;
    els.output.appendChild(line);
  } else {
    const line = document.createElement("div");
    line.className = `line-${level}`;
    line.textContent = trimmed;
    els.output.appendChild(line);
  }
  scrollOutputToBottom();
}

async function runSync(configName) {
  if (running) return;
  if (!configName) throw new Error("请填写配置文件名");

  running = true;
  els.runBtn.disabled = true;
  els.runStatus.textContent = "执行中…";
  els.runStatus.className = "status running";
  clearOutput();
  stickToBottom = true;
  els.scrollBottomBtn.classList.add("hidden");

  const body = {
    config: configName,
    group: els.runGroup.value || "1",
    verbose: els.optVerbose.checked,
    force: els.optForce.checked,
    post_sync: els.postSyncMode.value === "pick" ? "1" : els.postSyncMode.value,
  };

  if (els.postSyncMode.value === "pick") {
    body.post_commands = getSelectedPostCommands();
  }

  const res = await fetch("/api/run", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    appendOutput(err.error || "启动失败", "error");
    finishRun(1);
    return;
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split("\n\n");
    buffer = parts.pop() || "";

    for (const part of parts) {
      if (!part.trim()) continue;
      let event = "message";
      let dataLine = "";
      for (const line of part.split("\n")) {
        if (line.startsWith("event:")) event = line.slice(6).trim();
        if (line.startsWith("data:")) dataLine = line.slice(5).trim();
      }
      if (!dataLine) continue;
      const payload = JSON.parse(dataLine);
      if (event === "line") appendOutput(payload.text, payload.level || "info", payload.replace || "");
      if (event === "meta") appendOutput(payload.cmd, "meta");
      if (event === "done") finishRun(payload.code);
    }
  }
}

function finishRun(code) {
  running = false;
  els.runBtn.disabled = false;
  scrollOutputToBottom(true);
  if (code === 0) {
    els.runStatus.textContent = "完成";
    els.runStatus.className = "status ok";
  } else {
    els.runStatus.textContent = `失败 (${code})`;
    els.runStatus.className = "status fail";
  }
}

els.addGroupBtn.addEventListener("click", () => addGroup());

els.runGroup.addEventListener("change", () => {
  refreshPostSyncPicker();
  syncReplaceContext();
  if (!els.tabReplace.classList.contains("hidden")) {
    refreshReplacePanel();
  }
});

els.configName.addEventListener("input", onConfigNameChange);
els.postSyncMode.addEventListener("change", refreshPostSyncPicker);
els.postSyncSelectAll.addEventListener("click", () => {
  const boxes = $$(".post-cmd-check", els.postSyncList);
  const allChecked = boxes.every((b) => b.checked);
  boxes.forEach((b) => (b.checked = !allChecked));
});

// 仅当同步后命令相关字段变化时刷新勾选列表（避免认证切换等无关操作触发）
document.getElementById("configForm").addEventListener("change", (e) => {
  if (els.postSyncMode.value !== "pick") return;
  const t = e.target;
  if (!t) return;
  if (
    t.id === "defaultPostSync" ||
    t.classList.contains("group-post-sync") ||
    t.classList.contains("server-post-sync") ||
    t.classList.contains("group-name")
  ) {
    refreshPostSyncPicker();
  }
});

els.configSelect.addEventListener("change", async () => {
  const name = els.configSelect.value;
  if (!name) return;
  try {
    await loadConfig(name);
  } catch (e) {
    setSaveStatus(e.message, "error");
  }
});

els.demoBtn.addEventListener("click", async () => {
  try {
    await loadConfig("demo.yml");
  } catch (e) {
    setSaveStatus(e.message, "error");
  }
});

els.saveBtn.addEventListener("click", async () => {
  try {
    await saveConfig();
  } catch (e) {
    setSaveStatus(e.message, "error");
  }
});

els.runBtn.addEventListener("click", async () => {
  const name = configFileName();
  if (!name) {
    setSaveStatus("请先填写配置文件名", "error");
    return;
  }
  try {
    setSaveStatus(`执行 ${name}…`);
    await runSync(name);
  } catch (e) {
    setSaveStatus(e.message, "error");
    finishRun(1);
  }
});

els.output.addEventListener("scroll", updateScrollBottomBtn, { passive: true });

els.scrollBottomBtn.addEventListener("click", () => {
  stickToBottom = true;
  scrollOutputToBottom(true);
  els.scrollBottomBtn.classList.add("hidden");
});

els.clearOutputBtn.addEventListener("click", () => {
  els.output.innerHTML = '<div class="output-placeholder">点击「执行同步」开始，日志将在此实时显示</div>';
  els.runStatus.textContent = "等待执行";
  els.runStatus.className = "status";
  stickToBottom = true;
  els.scrollBottomBtn.classList.add("hidden");
});

bindGitAuthRadios();
fetchConfigs().then(() => loadConfig("demo.yml").catch(() => addGroup()));

/* ── Tabs ── */
$$(".panel-tabs .tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    $$(".panel-tabs .tab").forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");
    const name = tab.dataset.tab;
    els.tabConfig.classList.toggle("hidden", name !== "config");
    els.tabReplace.classList.toggle("hidden", name !== "replace");
    if (name === "replace") refreshReplacePanel();
  });
});

/* ── Replace 管理：前缀 + 文件/文件夹/压缩包；env 跟部署组 ── */
function syncReplaceContext() {
  const dir = effectiveReplaceDir() || "—";
  if (els.replaceDirView) els.replaceDirView.textContent = dir;
  const env = currentDeployEnv() || "—";
  const prefix = (els.replacePrefix?.value || "").trim().replace(/^\/+|\/+$/g, "");
  if (els.replaceEnvLabel) {
    els.replaceEnvLabel.textContent = prefix ? `env: ${env} · 前缀: ${prefix}/` : `env: ${env}`;
  }
}

function currentReplaceDir() {
  return effectiveReplaceDir();
}

function currentReplaceEnv() {
  return currentDeployEnv();
}

function currentReplacePrefix() {
  return (els.replacePrefix?.value || "").trim();
}

function clearReplaceEditor() {
  els.replaceFilePath.value = "";
  els.replaceFileContent.value = "";
  els.replaceFileContent.disabled = false;
}

async function refreshReplacePanel() {
  syncReplaceContext();
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  clearReplaceEditor();
  els.replaceFileList.innerHTML = "";

  if (!dir) {
    els.replaceFileList.innerHTML = '<div class="field-hint">请先填写配置名</div>';
    els.replaceFileStatus.textContent = "";
    return;
  }
  if (!env) {
    els.replaceFileList.innerHTML = '<div class="field-hint">请在服务器组填写 env，并用底部「部署组」选择</div>';
    els.replaceFileStatus.textContent = "当前部署组无 env";
    return;
  }
  await refreshReplaceFiles();
}

function buildReplaceTree(files) {
  const root = { dirs: {}, files: [] };
  for (const f of files) {
    const parts = f.path.split("/").filter(Boolean);
    if (!parts.length) continue;
    let node = root;
    for (let i = 0; i < parts.length - 1; i++) {
      const name = parts[i];
      if (!node.dirs[name]) node.dirs[name] = { name, dirs: {}, files: [] };
      node = node.dirs[name];
    }
    node.files.push(f);
  }
  return root;
}

function renderReplaceTree(node, container, prefix = "", depth = 0) {
  const dirNames = Object.keys(node.dirs || {}).sort((a, b) => a.localeCompare(b));
  for (const name of dirNames) {
    const child = node.dirs[name];
    const dirPath = prefix ? `${prefix}/${name}` : name;
    const wrap = document.createElement("div");
    wrap.className = "tree-dir";
    wrap.style.setProperty("--depth", String(depth));

    const row = document.createElement("div");
    row.className = "tree-row dir";

    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "tree-toggle";
    toggle.textContent = "▾";
    toggle.title = "折叠/展开";

    const check = document.createElement("input");
    check.type = "checkbox";
    check.className = "tree-check";
    check.dataset.dir = dirPath;

    const label = document.createElement("span");
    label.className = "tree-name";
    label.textContent = `${name}/`;

    const delBtn = document.createElement("button");
    delBtn.type = "button";
    delBtn.className = "tree-del";
    delBtn.textContent = "删";
    delBtn.title = `删除目录 ${dirPath}`;
    delBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      deleteReplaceNow({ dirs: [dirPath] });
    });

    const kids = document.createElement("div");
    kids.className = "tree-children";
    renderReplaceTree(child, kids, dirPath, depth + 1);

    toggle.addEventListener("click", () => {
      const closed = kids.classList.toggle("collapsed");
      toggle.textContent = closed ? "▸" : "▾";
    });

    check.addEventListener("change", () => {
      $$("input.tree-check", wrap).forEach((c) => {
        if (c !== check) c.checked = check.checked;
      });
    });

    row.append(toggle, check, label, delBtn);
    wrap.append(row, kids);
    container.appendChild(wrap);
  }

  const files = [...(node.files || [])].sort((a, b) => a.path.localeCompare(b.path));
  for (const f of files) {
    const name = f.path.split("/").pop();
    const row = document.createElement("div");
    row.className = "tree-row file";
    row.style.setProperty("--depth", String(depth));
    row.dataset.path = f.path;

    const spacer = document.createElement("span");
    spacer.className = "tree-toggle spacer";

    const check = document.createElement("input");
    check.type = "checkbox";
    check.className = "tree-check";
    check.dataset.path = f.path;

    const label = document.createElement("button");
    label.type = "button";
    label.className = "tree-name file-link";
    label.textContent = name;
    label.title = `${f.path} (${f.size}B)`;
    label.addEventListener("click", () => openReplaceFile(f.path));

    const delBtn = document.createElement("button");
    delBtn.type = "button";
    delBtn.className = "tree-del";
    delBtn.textContent = "删";
    delBtn.title = `删除 ${f.path}`;
    delBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      deleteReplaceNow({ paths: [f.path] });
    });

    row.append(spacer, check, label, delBtn);
    container.appendChild(row);
  }
}

function getReplaceSelection() {
  const paths = [];
  const dirs = [];
  $$("input.tree-check:checked", els.replaceFileList).forEach((c) => {
    if (c.dataset.dir) dirs.push(c.dataset.dir);
    if (c.dataset.path) paths.push(c.dataset.path);
  });
  // 目录已涵盖其子文件时，仍一并传 dirs；后端会展开
  return { paths, dirs };
}

async function parseJsonResponse(res) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    const snip = text.trim().slice(0, 80).replace(/\s+/g, " ");
    throw new Error(
      `接口返回非 JSON（HTTP ${res.status}）。请重启 UI 服务后再试。${snip ? " 响应: " + snip : ""}`
    );
  }
}

async function deleteReplaceNow({ paths = [], dirs = [] } = {}) {
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  if (!dir || !env) return;
  if (!paths.length && !dirs.length) {
    els.replaceFileStatus.textContent = "未选择要删除的项";
    return;
  }
  try {
    // 走已有 /api/replace/file，避免旧进程无 /delete 路由时返回 HTML 404
    const res = await fetch("/api/replace/file", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "delete_batch",
        replace_dir: dir,
        env,
        paths,
        dirs,
      }),
    });
    const data = await parseJsonResponse(res);
    if (!res.ok) throw new Error(data.error || "删除失败");
    const openPath = els.replaceFilePath.value.trim();
    const deleted = data.deleted || (data.ok && paths.length ? paths : []);
    if (openPath && deleted.includes(openPath)) clearReplaceEditor();
    // 单文件旧接口可能无 count
    const count = data.count != null ? data.count : deleted.length || paths.length + dirs.length;
    els.replaceFileStatus.textContent = `已删除 ${count} 个文件`;
    await refreshReplaceFiles();
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
}
async function refreshReplaceFiles() {
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  els.replaceFileList.innerHTML = "";
  replaceFilesCache = [];
  if (!dir || !env) return;
  try {
    const res = await fetch(
      `/api/replace/files?replace_dir=${encodeURIComponent(dir)}&env=${encodeURIComponent(env)}`
    );
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "加载文件失败");
    replaceFilesCache = data.files || [];
    if (!replaceFilesCache.length) {
      els.replaceFileList.innerHTML = '<div class="field-hint">暂无文件，请设置前缀后上传</div>';
      els.replaceFileStatus.textContent = `${dir}/${env} · 空`;
      return;
    }
    const tree = buildReplaceTree(replaceFilesCache);
    renderReplaceTree(tree, els.replaceFileList);
    const openPath = els.replaceFilePath.value.trim();
    if (openPath) {
      $$(".tree-row.file", els.replaceFileList).forEach((row) => {
        row.classList.toggle("active", row.dataset.path === openPath);
      });
    }
    els.replaceFileStatus.textContent = `${replaceFilesCache.length} 个文件 · 仅 ${env}`;
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
}

async function openReplaceFile(relPath) {
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  if (!dir || !env) return;
  try {
    const res = await fetch(
      `/api/replace/file?replace_dir=${encodeURIComponent(dir)}&env=${encodeURIComponent(env)}&path=${encodeURIComponent(relPath)}`
    );
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "读取失败");
    els.replaceFilePath.value = data.path;
    if (data.binary) {
      els.replaceFileContent.value = "";
      els.replaceFileContent.disabled = true;
      els.replaceFileStatus.textContent = "二进制文件，无法在此编辑（可重新上传覆盖）";
    } else {
      els.replaceFileContent.disabled = false;
      els.replaceFileContent.value = data.content;
      els.replaceFileStatus.textContent = `已打开 ${env}/${data.path}`;
    }
    $$(".tree-row.file", els.replaceFileList).forEach((row) => {
      row.classList.toggle("active", row.dataset.path === relPath);
    });
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
}
function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result;
      if (typeof result !== "string") {
        reject(new Error("读取失败"));
        return;
      }
      const i = result.indexOf(",");
      resolve(i >= 0 ? result.slice(i + 1) : result);
    };
    reader.onerror = () => reject(reader.error || new Error("读取失败"));
    reader.readAsDataURL(file);
  });
}

/** 与后端一致：跳过点目录 / 系统垃圾；允许 .env 等点文件 */
function shouldSkipReplacePath(relPath) {
  const parts = String(relPath || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);
  if (!parts.length) return true;
  const junk = new Set(["__macosx", ".ds_store", "thumbs.db"]);
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (junk.has(part.toLowerCase())) return true;
    // 仅跳过路径中间的点目录（.git/xxx），最后一段的 .env 保留
    if (i < parts.length - 1 && part.startsWith(".")) return true;
  }
  return false;
}

function hasParentDirSegment(relPath) {
  return String(relPath || "")
    .replace(/\\/g, "/")
    .split("/")
    .some((p) => p === "..");
}

/** 文件夹上传：保留嵌套；可选去掉选中文件夹顶层名 */
function relativePathFromUpload(file, isDir) {
  if (isDir && file.webkitRelativePath) {
    let parts = file.webkitRelativePath.split("/").filter(Boolean);
    if (els.replaceStripTop?.checked && parts.length > 1) {
      parts = parts.slice(1);
    }
    return parts.join("/") || file.name;
  }
  return file.name;
}

function requireReplaceTarget() {
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  if (!dir) {
    els.replaceFileStatus.textContent = "请先填写配置名";
    return null;
  }
  if (!env) {
    els.replaceFileStatus.textContent = "请先设置服务器组 env，并用底部部署组选择";
    return null;
  }
  return { dir, env, prefix: currentReplacePrefix() };
}

async function uploadReplaceSelection(fileList, isDir) {
  const target = requireReplaceTarget();
  if (!target) return;
  const all = [...fileList].filter((f) => f && f.name);
  // 单文件模式：允许 .env；只挡 .. 与系统垃圾名
  // 文件夹模式：再跳过 .git 等点目录（浏览器往往也不会带上隐藏文件）
  const files = all.filter((f) => {
    const path = relativePathFromUpload(f, isDir);
    if (!path || hasParentDirSegment(path)) return false;
    if (!isDir) {
      const base = path.split("/").pop().toLowerCase();
      return ![".ds_store", "thumbs.db"].includes(base);
    }
    return !shouldSkipReplacePath(path);
  });
  if (!files.length) {
    if (!all.length) {
      els.replaceFileStatus.textContent =
        "未选到文件。上传 .env 请用「上传文件」，并在系统文件框显示隐藏文件（macOS: ⌘⇧.）";
    } else {
      els.replaceFileStatus.textContent =
        `已选 ${all.length} 个均被跳过。点文件请用「上传文件」直接选 .env（文件夹上传时浏览器常忽略隐藏文件）`;
    }
    return;
  }

  const destHint = target.prefix ? `${target.env}/${target.prefix}/` : `${target.env}/`;
  els.replaceFileStatus.textContent = `正在上传 ${files.length} 个文件 → ${destHint}…`;
  try {
    const payload = [];
    for (const f of files) {
      const path = relativePathFromUpload(f, isDir);
      if (!path || hasParentDirSegment(path)) continue;
      payload.push({ path, content_b64: await fileToBase64(f) });
    }
    if (!payload.length) throw new Error("没有可上传的路径");

    const res = await fetch("/api/replace/upload", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        replace_dir: target.dir,
        env: target.env,
        prefix: target.prefix,
        files: payload,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "上传失败");
    els.replaceFileStatus.textContent = `已写入 ${data.count} 个文件 → ${destHint}`;
    await refreshReplaceFiles();
    if (data.saved?.[0]) openReplaceFile(data.saved[0]);
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
}

async function uploadReplaceArchive(file) {
  const target = requireReplaceTarget();
  if (!target) return;
  const name = file.name || "";
  const lower = name.toLowerCase();
  if (!(/\.(zip|tar|tgz)$/.test(lower) || lower.endsWith(".tar.gz"))) {
    els.replaceFileStatus.textContent = "仅支持 .zip / .tar.gz / .tgz / .tar";
    return;
  }
  const destHint = target.prefix ? `${target.env}/${target.prefix}/` : `${target.env}/`;
  els.replaceFileStatus.textContent = `正在解压 ${name} → ${destHint}…`;
  try {
    const res = await fetch("/api/replace/archive", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        replace_dir: target.dir,
        env: target.env,
        prefix: target.prefix,
        filename: name,
        content_b64: await fileToBase64(file),
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "解压失败");
    els.replaceFileStatus.textContent = `已解压 ${data.count} 个文件 → ${destHint}`;
    await refreshReplaceFiles();
    if (data.saved?.[0]) openReplaceFile(data.saved[0]);
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
}

els.replaceDir.addEventListener("input", syncReplaceContext);
els.replacePrefix?.addEventListener("input", syncReplaceContext);

document.getElementById("configForm").addEventListener("input", (e) => {
  if (e.target?.classList?.contains("group-env")) {
    syncReplaceContext();
    if (!els.tabReplace.classList.contains("hidden")) refreshReplacePanel();
  }
});

els.replaceRefreshBtn.addEventListener("click", () => refreshReplacePanel());

els.replaceUploadFilesBtn.addEventListener("click", () => els.replaceUploadFiles.click());
els.replaceUploadDirBtn.addEventListener("click", () => els.replaceUploadDir.click());
els.replaceUploadArchiveBtn.addEventListener("click", () => els.replaceUploadArchive.click());

els.replaceUploadFiles.addEventListener("change", async () => {
  const list = els.replaceUploadFiles.files;
  if (list?.length) await uploadReplaceSelection(list, false);
  els.replaceUploadFiles.value = "";
});

els.replaceUploadDir.addEventListener("change", async () => {
  const list = els.replaceUploadDir.files;
  if (list?.length) await uploadReplaceSelection(list, true);
  els.replaceUploadDir.value = "";
});

els.replaceUploadArchive.addEventListener("change", async () => {
  const file = els.replaceUploadArchive.files?.[0];
  if (file) await uploadReplaceArchive(file);
  els.replaceUploadArchive.value = "";
});

els.replaceSaveFileBtn.addEventListener("click", async () => {
  const dir = currentReplaceDir();
  const env = currentReplaceEnv();
  const rel = els.replaceFilePath.value.trim();
  if (!dir || !env || !rel) {
    els.replaceFileStatus.textContent = "请先打开一个已上传的文件再编辑保存";
    return;
  }
  if (els.replaceFileContent.disabled) {
    els.replaceFileStatus.textContent = "二进制文件请重新上传覆盖";
    return;
  }
  try {
    const res = await fetch("/api/replace/file", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "save",
        replace_dir: dir,
        env,
        path: rel,
        content: els.replaceFileContent.value,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "保存失败");
    els.replaceFileStatus.textContent = `已保存 ${env}/${data.path}`;
    await refreshReplaceFiles();
    openReplaceFile(rel);
  } catch (e) {
    els.replaceFileStatus.textContent = e.message;
  }
});

els.replaceSelectAllBtn.addEventListener("click", () => {
  const boxes = $$("input.tree-check", els.replaceFileList);
  if (!boxes.length) return;
  const allOn = boxes.every((b) => b.checked);
  boxes.forEach((b) => (b.checked = !allOn));
});

els.replaceDeleteSelectedBtn.addEventListener("click", () => {
  const { paths, dirs } = getReplaceSelection();
  // 未勾选时：若编辑器有打开文件，直接删当前文件（无确认）
  if (!paths.length && !dirs.length) {
    const rel = els.replaceFilePath.value.trim();
    if (rel) deleteReplaceNow({ paths: [rel] });
    else els.replaceFileStatus.textContent = "未选择要删除的项";
    return;
  }
  deleteReplaceNow({ paths, dirs });
});
