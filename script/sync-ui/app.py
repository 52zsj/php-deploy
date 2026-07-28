#!/usr/bin/env python3
"""本地 Web 配置界面：表单编辑 YAML 并执行 sync.sh，流式输出日志。"""

from __future__ import annotations

import base64
import fcntl
import io
import json
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import termios
import tarfile
import threading
import webbrowser
import zipfile
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

UI_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = UI_DIR.parent.parent
# Docker：DATA_CONFIGS=/data/configs；本机默认 data/configs（与 Docker 共用）
_CONFIG_ENV = (os.environ.get("DATA_CONFIGS") or os.environ.get("GITSHIP_CONFIG_DIR") or "").strip()
CONFIG_DIR = Path(_CONFIG_ENV).expanduser() if _CONFIG_ENV else (PROJECT_ROOT / "data" / "configs")
STATIC_DIR = UI_DIR / "static"
DEFAULT_PORT = 8765


def ensure_config_seed() -> None:
    """缺 demo 时从 config.seed/ 拷贝；兼容旧 yml/ 迁移到 data/configs。"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("demo.yml", "demo-dir.yml"):
        dest = CONFIG_DIR / name
        if dest.is_file():
            continue
        for src_dir in (PROJECT_ROOT / "config.seed", PROJECT_ROOT / "yml.seed"):
            src = src_dir / name
            if src.is_file():
                dest.write_bytes(src.read_bytes())
                break
    legacy = PROJECT_ROOT / "yml"
    if legacy.is_dir() and legacy.resolve() != CONFIG_DIR.resolve():
        for src in list(legacy.glob("*.yml")) + list(legacy.glob("*.yaml")):
            if src.is_symlink():
                continue
            dest = CONFIG_DIR / src.name
            if not dest.exists():
                dest.write_bytes(src.read_bytes())


ensure_config_seed()
# CSI / OSC / 其他终端控制序列
CSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC_RE = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)")
# git 本地下载进度（Receiving/Resolving）→ UI 单行原地刷新
GIT_PROGRESS_DONE_RE = re.compile(r"\bdone\.?\s*$")
GIT_LOCAL_PROGRESS_RE = re.compile(r"^(?:Receiving|Resolving) objects:")
GIT_REMOTE_PROGRESS_RE = re.compile(
    r"^remote:\s*(?:Enumerating|Counting|Compressing|Receiving|Resolving|Unpacking) objects"
)
ANSI_RE = re.compile(r"\x1b[@-Z\\-_]")
# ESC 丢失后残留的 rsync progress 片段，如 [1A [K
ORPHAN_CSI_RE = re.compile(r"\[(?:\d+[ABCDGJKSTfmnsu]|K|J|H)\??")
HAS_YQ = shutil.which("yq") is not None
HAS_STDBUF = shutil.which("stdbuf") is not None

try:
    import yaml as pyyaml

    HAS_PYYAML = True
except ImportError:
    pyyaml = None
    HAS_PYYAML = False


def ensure_yaml_backend() -> None:
    if HAS_YQ or HAS_PYYAML:
        return
    print("需要 yq 或 PyYAML（pip3 install pyyaml）", file=sys.stderr)
    sys.exit(1)


def yaml_load(path: Path) -> dict:
    if HAS_YQ:
        result = subprocess.run(
            ["yq", "-o=json", str(path)],
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout or "{}")
    assert pyyaml is not None
    with path.open("r", encoding="utf-8") as f:
        return pyyaml.safe_load(f) or {}


def yaml_dump(path: Path, data: dict) -> None:
    if HAS_YQ:
        result = subprocess.run(
            ["yq", "-P", "-o=yaml", "."],
            input=json.dumps(data, ensure_ascii=False),
            capture_output=True,
            text=True,
            check=True,
        )
        path.write_text(result.stdout, encoding="utf-8")
        return
    assert pyyaml is not None
    with path.open("w", encoding="utf-8") as f:
        pyyaml.safe_dump(data, f, allow_unicode=True, sort_keys=False, default_flow_style=False)


def list_configs() -> list[str]:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    configs = sorted(p.name for p in CONFIG_DIR.glob("*.yml") if p.is_file())
    return configs


SECRETS_DIR = PROJECT_ROOT / ".secrets"
SECRET_REF_RE = re.compile(r"^secret:(.+)$")
ENV_REF_RE = re.compile(r"^env:(.+)$")


def secrets_path(stem: str) -> Path:
    return SECRETS_DIR / f"{stem}.env"


def read_secrets_file(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        if key:
            result[key] = val
    return result


def write_secrets_file(path: Path, data: dict[str, str]) -> None:
    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    lines = [f"{k}={v}" for k, v in sorted(data.items()) if v is not None and str(v) != ""]
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    os.chmod(path, 0o600)


def resolve_ref(value: str, secrets: dict[str, str]) -> str:
    """解析 secret:/env: 引用；无法解析时返回空串。"""
    if value is None:
        return ""
    text = str(value)
    m = SECRET_REF_RE.match(text)
    if m:
        return secrets.get(m.group(1), "")
    m = ENV_REF_RE.match(text)
    if m:
        return os.environ.get(m.group(1), "")
    return text


def is_secret_ref(value: str) -> bool:
    return bool(value) and (SECRET_REF_RE.match(str(value)) or ENV_REF_RE.match(str(value)))


def sanitize_key(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_") or "KEY"


def expand_user_path(path: str) -> Path:
    """与 sync.sh expand_path 一致：~ / ./ / 相对路径。"""
    text = (path or "").strip()
    if not text:
        return PROJECT_ROOT / "replace"
    if text == "~":
        return Path.home()
    if text.startswith("~/"):
        return Path.home() / text[2:]
    if text.startswith("./"):
        return (PROJECT_ROOT / text[2:]).resolve()
    p = Path(text)
    if p.is_absolute():
        return p.resolve()
    return (PROJECT_ROOT / p).resolve()


def safe_join(base: Path, *parts: str) -> Path:
    """确保结果仍在 base 目录下，防止路径穿越。"""
    base_r = base.resolve()
    target = base_r
    for part in parts:
        part = (part or "").strip().lstrip("/")
        if not part:
            continue
        if ".." in Path(part).parts:
            raise ValueError("非法路径")
        target = target / part
    target = target.resolve()
    base_s = str(base_r)
    tgt_s = str(target)
    if tgt_s != base_s and not tgt_s.startswith(base_s + os.sep):
        raise ValueError("路径越界")
    return target


def list_replace_envs(replace_dir: str) -> dict:
    base = expand_user_path(replace_dir)
    base.mkdir(parents=True, exist_ok=True)
    envs = sorted(
        [p.name for p in base.iterdir() if p.is_dir() and not p.name.startswith(".")],
        key=str.lower,
    )
    return {"base": str(base), "envs": envs}


def list_replace_files(replace_dir: str, env: str) -> dict:
    env = _validate_replace_env(env)
    base = expand_user_path(replace_dir)
    env_dir = safe_join(base, env)
    if not env_dir.is_dir():
        return {"base": str(base), "env": env, "files": []}
    files = []
    for p in sorted(env_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(env_dir)).replace("\\", "/")
        files.append({"path": rel, "size": p.stat().st_size})
    return {"base": str(base), "env": env, "files": files}


def read_replace_file(replace_dir: str, env: str, rel_path: str) -> dict:
    env = _validate_replace_env(env)
    rel_path = _validate_rel_path(rel_path)
    base = expand_user_path(replace_dir)
    path = safe_join(base, env, rel_path)
    if not path.is_file():
        raise FileNotFoundError(rel_path)
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
        binary = False
    except UnicodeDecodeError:
        text = ""
        binary = True
    return {
        "path": rel_path.replace("\\", "/"),
        "content": text,
        "binary": binary,
        "size": len(raw),
    }


def _validate_replace_env(env: str) -> str:
    env = (env or "").strip()
    if not env or ".." in env or "/" in env or "\\" in env:
        raise ValueError("无效 env")
    if not re.match(r"^[A-Za-z0-9_.-]+$", env):
        raise ValueError("env 仅允许字母数字._-")
    return env


def _validate_rel_path(rel_path: str) -> str:
    rel_path = (rel_path or "").replace("\\", "/").lstrip("/")
    if not rel_path or ".." in Path(rel_path).parts:
        raise ValueError("非法文件路径")
    return rel_path


def write_replace_file(replace_dir: str, env: str, rel_path: str, content: str) -> dict:
    env = _validate_replace_env(env)
    rel_path = _validate_rel_path(rel_path)
    base = expand_user_path(replace_dir)
    path = safe_join(base, env, rel_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content if content is not None else "", encoding="utf-8")
    return {"ok": True, "path": rel_path, "size": path.stat().st_size}


def write_replace_bytes(replace_dir: str, env: str, rel_path: str, data: bytes) -> dict:
    """写入二进制内容到指定 env 目录（与其它 env 互不影响）。"""
    env = _validate_replace_env(env)
    rel_path = _validate_rel_path(rel_path)
    base = expand_user_path(replace_dir)
    env_dir = safe_join(base, env)
    env_dir.mkdir(parents=True, exist_ok=True)
    path = safe_join(base, env, rel_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return {"ok": True, "path": rel_path, "size": len(data)}


MAX_UPLOAD_FILES = 200
MAX_UPLOAD_BYTES = 2 * 1024 * 1024  # 单文件 2MB
MAX_ARCHIVE_BYTES = 20 * 1024 * 1024  # 压缩包 20MB
# 目录同步工作区：静态站可能更大
MAX_DIR_UPLOAD_FILES = 5000
MAX_DIR_UPLOAD_BYTES = 50 * 1024 * 1024
MAX_DIR_ARCHIVE_BYTES = 200 * 1024 * 1024
UPLOADS_DIRNAME = "data/uploads"
SSH_DIRNAME = "data/ssh"
REPOS_DIRNAME = "data/repos"


def data_ssh_dir() -> Path:
    env = (os.environ.get("DATA_SSH") or "").strip()
    root = Path(env).expanduser() if env else (PROJECT_ROOT / SSH_DIRNAME)
    root.mkdir(parents=True, exist_ok=True)
    return root.resolve()


def data_uploads_dir() -> Path:
    env = (os.environ.get("DATA_UPLOADS") or "").strip()
    root = Path(env).expanduser() if env else (PROJECT_ROOT / UPLOADS_DIRNAME)
    root.mkdir(parents=True, exist_ok=True)
    return root.resolve()


def data_repos_dir() -> Path:
    env = (os.environ.get("DATA_REPOS") or "").strip()
    root = Path(env).expanduser() if env else (PROJECT_ROOT / REPOS_DIRNAME)
    root.mkdir(parents=True, exist_ok=True)
    return root.resolve()


def _safe_ssh_filename(name: str) -> str:
    base = Path(name or "").name.strip()
    if not base or base in (".", "..") or ".." in base:
        raise ValueError("无效的密钥文件名")
    if base.startswith(".") and base not in (".gitkeep",):
        # 允许 known_hosts / config，禁止隐藏乱路径
        if base not in ("known_hosts", "config", "authorized_keys"):
            pass
    return base


def list_ssh_keys() -> dict:
    root = data_ssh_dir()
    keys = []
    for p in sorted(root.iterdir(), key=lambda x: x.name.lower()):
        if not p.is_file():
            continue
        if p.name in (".gitkeep",) or p.name.endswith(".md"):
            continue
        if p.name.endswith(".pub"):
            continue
        keys.append(
            {
                "name": p.name,
                "path": f"./data/ssh/{p.name}",
                "size": p.stat().st_size,
            }
        )
    return {"ok": True, "dir": str(root), "keys": keys, "default": "./data/ssh/id_rsa"}


def upload_ssh_key(filename: str, content_b64: str) -> dict:
    name = _safe_ssh_filename(filename)
    raw = base64.b64decode(content_b64 or "")
    if not raw:
        raise ValueError("密钥内容为空")
    if len(raw) > 256 * 1024:
        raise ValueError("密钥文件过大")
    dest = data_ssh_dir() / name
    dest.write_bytes(raw)
    try:
        dest.chmod(0o600)
    except OSError:
        pass
    # Docker：同步到 ~/.ssh，兼容旧配置路径
    home_ssh = Path.home() / ".ssh"
    try:
        home_ssh.mkdir(mode=0o700, parents=True, exist_ok=True)
        mirror = home_ssh / name
        mirror.write_bytes(raw)
        mirror.chmod(0o600)
    except OSError:
        pass
    return {"ok": True, "name": name, "path": f"./data/ssh/{name}", **list_ssh_keys()}


def delete_ssh_key(filename: str) -> dict:
    name = _safe_ssh_filename(filename)
    dest = data_ssh_dir() / name
    if dest.is_file():
        dest.unlink()
    mirror = Path.home() / ".ssh" / name
    if mirror.is_file() and mirror.resolve() != dest.resolve():
        try:
            mirror.unlink()
        except OSError:
            pass
    return list_ssh_keys()

ARCHIVE_SKIP_NAMES = {"__macosx", ".ds_store", "thumbs.db"}


def _should_skip_replace_path(rel: str) -> bool:
    """跳过点目录（.git/.cursor/…）与系统垃圾名；允许 .env / .htaccess 等点文件。"""
    parts = Path((rel or "").replace("\\", "/")).parts
    if not parts:
        return True
    for i, part in enumerate(parts):
        lower = part.lower()
        if lower in ARCHIVE_SKIP_NAMES:
            return True
        # 非最后一段且以 . 开头 → 点目录
        if i < len(parts) - 1 and part.startswith("."):
            return True
    return False


def _normalize_prefix(prefix: str) -> str:
    """相对路径前缀，如 application 或 application/config；可空。"""
    p = (prefix or "").replace("\\", "/").strip().strip("/")
    if not p:
        return ""
    if ".." in Path(p).parts:
        raise ValueError("非法路径前缀")
    return p


def _with_prefix(prefix: str, rel: str) -> str:
    pref = _normalize_prefix(prefix)
    rel = _validate_rel_path(rel)
    return f"{pref}/{rel}" if pref else rel


def _should_skip_archive_member(rel: str) -> bool:
    return _should_skip_replace_path(rel)


def project_markers(local_dir: str = "", project_name: str = "") -> list[str]:
    """用于从绝对路径里识别「项目根」的目录名候选。"""
    markers: list[str] = []
    name = (project_name or "").strip().replace(".yml", "")
    if name:
        markers.append(name)
    ld = (local_dir or "").strip().rstrip("/")
    if ld:
        base = Path(ld).name
        if base and base not in markers:
            markers.append(base)
    return markers


def relativize_under_project(source: Path, local_dir: str = "", project_name: str = "") -> str:
    """
    把本机绝对路径变成相对仓库根的路径。
    优先：落在 local_dir 下；否则在路径中找项目目录名（如 feature_latter），取其之后的部分。
    """
    source = source.resolve()
    markers = project_markers(local_dir, project_name)

    ld = (local_dir or "").strip()
    if ld:
        try:
            root = expand_user_path(ld).resolve()
            rel = source.relative_to(root)
            text = str(rel).replace("\\", "/")
            return "" if text == "." else text
        except ValueError:
            pass

    parts = list(source.parts)
    for marker in markers:
        if marker in parts:
            idx = parts.index(marker)
            after = parts[idx + 1 :]
            if not after:
                return ""
            return "/".join(after)

    raise ValueError(
        "无法识别相对项目根的路径：请确认路径落在「本地目录」下，"
        "或绝对路径中包含项目名（配置名 / 本地目录最后一级）"
    )


def import_replace_from_path(
    replace_dir: str,
    env: str,
    source_path: str,
    local_dir: str = "",
    project_name: str = "",
) -> dict:
    """
    从本机路径导入：自动算出相对仓库根的路径并写入 replace_dir/env/。
    例：source=/.../feature_latter/config/wxpay → 写入 env/config/wxpay/...
    """
    env = _validate_replace_env(env)
    raw = (source_path or "").strip()
    if not raw:
        raise ValueError("请填写源路径")

    # 相对路径：相对 local_dir（项目检出）
    src_candidate = Path(raw)
    if not src_candidate.is_absolute() and not raw.startswith("~") and not raw.startswith("./"):
        ld = (local_dir or "").strip()
        if not ld:
            raise ValueError("相对路径需要先填写配置里的「本地目录」")
        src = expand_user_path(ld) / raw
    else:
        src = expand_user_path(raw)

    if not src.exists():
        raise ValueError(f"路径不存在: {src}")

    # 源是文件 / 目录时，先确定「导入根」相对路径
    if src.is_file():
        rel_root = relativize_under_project(src, local_dir, project_name)
        if not rel_root:
            raise ValueError("导入结果落在项目根本身，请指定具体文件或子目录")
        data = src.read_bytes()
        if len(data) > MAX_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_UPLOAD_BYTES}B）: {rel_root}")
        write_replace_bytes(replace_dir, env, rel_root, data)
        base = expand_user_path(replace_dir)
        return {
            "ok": True,
            "env": env,
            "base": str(base),
            "relative_root": str(Path(rel_root).parent).replace("\\", "/")
            if "/" in rel_root
            else "",
            "saved": [rel_root],
            "count": 1,
        }

    # 目录：目录本身相对项目根 + 其下所有文件（允许 .env；跳过 .git 等点目录）
    dir_rel = relativize_under_project(src, local_dir, project_name)
    files = [p for p in sorted(src.rglob("*")) if p.is_file()]
    files = [
        p
        for p in files
        if not _should_skip_replace_path(str(p.relative_to(src)).replace("\\", "/"))
    ]
    if not files:
        raise ValueError("目录下没有可导入的文件")
    if len(files) > MAX_UPLOAD_FILES:
        raise ValueError(f"一次最多导入 {MAX_UPLOAD_FILES} 个文件")

    saved = []
    for p in files:
        inner = str(p.relative_to(src)).replace("\\", "/")
        rel = f"{dir_rel}/{inner}" if dir_rel else inner
        rel = _validate_rel_path(rel)
        data = p.read_bytes()
        if len(data) > MAX_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_UPLOAD_BYTES}B）: {rel}")
        write_replace_bytes(replace_dir, env, rel, data)
        saved.append(rel)

    base = expand_user_path(replace_dir)
    return {
        "ok": True,
        "env": env,
        "base": str(base),
        "relative_root": dir_rel or ".",
        "saved": saved,
        "count": len(saved),
    }


def upload_replace_files(replace_dir: str, env: str, files: list, prefix: str = "") -> dict:
    """批量上传到 replace_dir/env/[prefix]/，各 env 目录相互独立。"""
    env = _validate_replace_env(env)
    pref = _normalize_prefix(prefix)
    if not isinstance(files, list) or not files:
        raise ValueError("没有可上传的文件")
    if len(files) > MAX_UPLOAD_FILES:
        raise ValueError(f"一次最多上传 {MAX_UPLOAD_FILES} 个文件")

    saved = []
    for item in files:
        if not isinstance(item, dict):
            raise ValueError("文件项格式错误")
        rel = _with_prefix(pref, item.get("path") or "")
        raw_b64 = item.get("content_b64")
        if raw_b64 is not None:
            try:
                data = base64.b64decode(raw_b64)
            except Exception as exc:
                raise ValueError(f"解码失败: {rel}") from exc
        else:
            content = item.get("content")
            if content is None:
                raise ValueError(f"缺少内容: {rel}")
            data = str(content).encode("utf-8")
        if len(data) > MAX_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_UPLOAD_BYTES}B）: {rel}")
        write_replace_bytes(replace_dir, env, rel, data)
        saved.append(rel)

    base = expand_user_path(replace_dir)
    return {
        "ok": True,
        "env": env,
        "prefix": pref,
        "base": str(base),
        "saved": saved,
        "count": len(saved),
    }


def _archive_kind(filename: str) -> str:
    name = (filename or "").lower().strip()
    if name.endswith(".tar.gz") or name.endswith(".tgz"):
        return "tar.gz"
    if name.endswith(".tar"):
        return "tar"
    if name.endswith(".zip"):
        return "zip"
    raise ValueError("仅支持 .zip / .tar.gz / .tgz / .tar")


def _iter_zip_members(data: bytes):
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            rel = info.filename.replace("\\", "/")
            if rel.endswith("/"):
                continue
            yield rel, zf.read(info)


def _iter_tar_members(data: bytes):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
        for member in tf.getmembers():
            if not member.isfile():
                continue
            rel = member.name.replace("\\", "/")
            extracted = tf.extractfile(member)
            if extracted is None:
                continue
            yield rel, extracted.read()


def extract_replace_archive(
    replace_dir: str,
    env: str,
    filename: str,
    content_b64: str,
    prefix: str = "",
) -> dict:
    """解压压缩包到 replace_dir/env/[prefix]/，防 zip/tar slip。"""
    env = _validate_replace_env(env)
    pref = _normalize_prefix(prefix)
    kind = _archive_kind(filename)
    try:
        raw = base64.b64decode(content_b64 or "")
    except Exception as exc:
        raise ValueError("压缩包解码失败") from exc
    if not raw:
        raise ValueError("压缩包为空")
    if len(raw) > MAX_ARCHIVE_BYTES:
        raise ValueError(f"压缩包过大（>{MAX_ARCHIVE_BYTES}B）")

    members = list(_iter_zip_members(raw) if kind == "zip" else _iter_tar_members(raw))
    if not members:
        raise ValueError("压缩包内没有可导入的文件")
    if len(members) > MAX_UPLOAD_FILES:
        raise ValueError(f"压缩包内文件过多（最多 {MAX_UPLOAD_FILES}）")

    saved = []
    for rel_raw, data in members:
        rel_raw = rel_raw.lstrip("/")
        if not rel_raw or ".." in Path(rel_raw).parts:
            raise ValueError(f"非法压缩包路径: {rel_raw}")
        if _should_skip_archive_member(rel_raw):
            continue
        if len(data) > MAX_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_UPLOAD_BYTES}B）: {rel_raw}")
        rel = _with_prefix(pref, rel_raw)
        write_replace_bytes(replace_dir, env, rel, data)
        saved.append(rel)

    if not saved:
        raise ValueError("解压后无有效文件（可能全是系统垃圾文件）")

    base = expand_user_path(replace_dir)
    return {
        "ok": True,
        "env": env,
        "prefix": pref,
        "base": str(base),
        "saved": saved,
        "count": len(saved),
    }


def _cleanup_empty_dirs(env_root: Path, start: Path) -> None:
    parent = start
    while parent != env_root and parent.is_dir() and not any(parent.iterdir()):
        parent.rmdir()
        parent = parent.parent


def delete_replace_file(replace_dir: str, env: str, rel_path: str) -> dict:
    env = _validate_replace_env(env)
    rel_path = _validate_rel_path(rel_path)
    base = expand_user_path(replace_dir)
    path = safe_join(base, env, rel_path)
    if not path.is_file():
        raise FileNotFoundError(rel_path)
    path.unlink()
    env_root = safe_join(base, env)
    _cleanup_empty_dirs(env_root, path.parent)
    return {"ok": True}


def delete_replace_batch(replace_dir: str, env: str, paths: list | None = None, dirs: list | None = None) -> dict:
    """批量删除文件；dirs 为目录前缀，删除该前缀下全部文件（无确认）。"""
    env = _validate_replace_env(env)
    base = expand_user_path(replace_dir)
    env_root = safe_join(base, env)
    if not env_root.is_dir():
        return {"ok": True, "deleted": [], "count": 0}

    to_delete: set[str] = set()
    for p in paths or []:
        to_delete.add(_validate_rel_path(str(p)))

    for d in dirs or []:
        d = (d or "").replace("\\", "/").strip().strip("/")
        if not d or ".." in Path(d).parts:
            raise ValueError(f"非法目录: {d}")
        dir_path = safe_join(base, env, d)
        if not dir_path.is_dir():
            continue
        for f in dir_path.rglob("*"):
            if f.is_file():
                to_delete.add(str(f.relative_to(env_root)).replace("\\", "/"))

    deleted = []
    for rel in sorted(to_delete):
        path = safe_join(base, env, rel)
        if path.is_file():
            path.unlink()
            deleted.append(rel)
            _cleanup_empty_dirs(env_root, path.parent)

    return {"ok": True, "deleted": deleted, "count": len(deleted)}


def ensure_replace_env(replace_dir: str, env: str) -> dict:
    env = _validate_replace_env(env)
    base = expand_user_path(replace_dir)
    env_dir = safe_join(base, env)
    env_dir.mkdir(parents=True, exist_ok=True)
    return {"ok": True, "env": env, "path": str(env_dir)}


def _uploads_root() -> Path:
    return data_uploads_dir()


def resolve_upload_workdir(config_name: str) -> Path:
    """配置名 → data/uploads/<stem>/（Docker 映射持久化）。"""
    stem = Path(config_name or "").name
    if stem.endswith(".yml"):
        stem = stem[:-4]
    stem = stem.strip()
    if not stem or ".." in stem or "/" in stem or "\\" in stem:
        raise ValueError("无效的配置名")
    root = _uploads_root()
    dest = root / stem
    dest.mkdir(parents=True, exist_ok=True)
    dest.resolve().relative_to(root.resolve())
    return dest


def dir_upload_status(config_name: str) -> dict:
    dest = resolve_upload_workdir(config_name)
    files = [p for p in dest.rglob("*") if p.is_file()]
    total = sum(p.stat().st_size for p in files)
    rel = f"./data/uploads/{dest.name}"
    return {
        "ok": True,
        "source_dir": rel,
        "abs_path": str(dest),
        "file_count": len(files),
        "total_bytes": total,
        "empty": len(files) == 0,
    }


def clear_dir_workdir(config_name: str) -> Path:
    dest = resolve_upload_workdir(config_name)
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)
    return dest


def _should_skip_dir_upload_path(rel: str) -> bool:
    parts = [p for p in rel.replace("\\", "/").split("/") if p]
    if not parts:
        return True
    junk = {"__macosx", ".ds_store", "thumbs.db"}
    for i, part in enumerate(parts):
        if part.lower() in junk:
            return True
        if i < len(parts) - 1 and part.startswith("."):
            return True
    return False


def upload_dir_files(config_name: str, files: list, clear: bool = True) -> dict:
    """上传文件列表到 .uploads/<config>/；默认先清空再写入。"""
    if not isinstance(files, list) or not files:
        raise ValueError("没有可上传的文件")
    if len(files) > MAX_DIR_UPLOAD_FILES:
        raise ValueError(f"一次最多上传 {MAX_DIR_UPLOAD_FILES} 个文件")

    dest = clear_dir_workdir(config_name) if clear else resolve_upload_workdir(config_name)
    saved = []
    for item in files:
        if not isinstance(item, dict):
            raise ValueError("文件项格式错误")
        rel = (item.get("path") or "").replace("\\", "/").lstrip("/")
        if not rel or ".." in Path(rel).parts:
            raise ValueError(f"非法路径: {rel}")
        if _should_skip_dir_upload_path(rel):
            continue
        raw_b64 = item.get("content_b64")
        if raw_b64 is None:
            raise ValueError(f"缺少内容: {rel}")
        try:
            data = base64.b64decode(raw_b64)
        except Exception as exc:
            raise ValueError(f"解码失败: {rel}") from exc
        if len(data) > MAX_DIR_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_DIR_UPLOAD_BYTES}B）: {rel}")
        out = safe_join(dest, rel)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        saved.append(rel)

    if not saved:
        raise ValueError("没有写入任何文件（可能被过滤）")
    status = dir_upload_status(config_name)
    status["saved"] = saved
    status["count"] = len(saved)
    return status


def extract_dir_archive(config_name: str, filename: str, content_b64: str, clear: bool = True) -> dict:
    """解压压缩包到 .uploads/<config>/。"""
    kind = _archive_kind(filename)
    try:
        raw = base64.b64decode(content_b64 or "")
    except Exception as exc:
        raise ValueError("压缩包解码失败") from exc
    if not raw:
        raise ValueError("压缩包为空")
    if len(raw) > MAX_DIR_ARCHIVE_BYTES:
        raise ValueError(f"压缩包过大（>{MAX_DIR_ARCHIVE_BYTES}B）")

    members = list(_iter_zip_members(raw) if kind == "zip" else _iter_tar_members(raw))
    if not members:
        raise ValueError("压缩包内没有可导入的文件")
    if len(members) > MAX_DIR_UPLOAD_FILES:
        raise ValueError(f"压缩包内文件过多（最多 {MAX_DIR_UPLOAD_FILES}）")

    dest = clear_dir_workdir(config_name) if clear else resolve_upload_workdir(config_name)
    saved = []
    for rel_raw, data in members:
        rel_raw = rel_raw.lstrip("/")
        if not rel_raw or ".." in Path(rel_raw).parts:
            raise ValueError(f"非法压缩包路径: {rel_raw}")
        if _should_skip_dir_upload_path(rel_raw) or _should_skip_archive_member(rel_raw):
            continue
        if len(data) > MAX_DIR_UPLOAD_BYTES:
            raise ValueError(f"文件过大（>{MAX_DIR_UPLOAD_BYTES}B）: {rel_raw}")
        out = safe_join(dest, rel_raw)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        saved.append(rel_raw)

    if not saved:
        raise ValueError("压缩包内没有可写入的文件")
    status = dir_upload_status(config_name)
    status["saved"] = saved
    status["count"] = len(saved)
    return status


def load_config(name: str) -> dict:
    safe = Path(name).name
    path = CONFIG_DIR / safe
    if not path.is_file() or ".." in name or not safe.endswith(".yml"):
        raise FileNotFoundError(name)
    data = yaml_load(path)
    stem = path.stem
    secrets = read_secrets_file(secrets_path(stem))

    # 界面永不回填真实密码：只告知是否已有密钥
    display = json.loads(json.dumps(data))  # deep copy
    gitee = display.get("gitee")
    if isinstance(gitee, dict) and gitee.get("auth_type") == "password":
        raw_pw = gitee.get("password") or ""
        has = bool(is_secret_ref(raw_pw) or (raw_pw and not is_secret_ref(raw_pw)) or secrets.get("GITEE_PASSWORD"))
        gitee["password"] = ""
        gitee["_password_saved"] = has
    for group in display.get("server_groups") or []:
        if not isinstance(group, dict):
            continue
        for server in group.get("servers") or []:
            if not isinstance(server, dict):
                continue
            if server.get("auth_type") == "password":
                raw = server.get("auth_info") or ""
                srv_name = server.get("name") or ""
                key = f"SERVER_{sanitize_key(srv_name)}" if srv_name else ""
                has = bool(
                    is_secret_ref(raw)
                    or (raw and not is_secret_ref(raw) and not str(raw).startswith("~") and not str(raw).startswith("/"))
                    or (key and secrets.get(key))
                )
                server["auth_info"] = ""
                server["_auth_info_saved"] = has

    return {
        "config_name": stem,
        "raw": display,
    }


def externalize_secrets(stem: str, payload: dict, previous: dict | None = None) -> dict:
    """把明文密码写入 .secrets，yml 中改为 secret: 引用。空密码且已有引用则保留。"""
    if not isinstance(payload, dict):
        raise ValueError("配置内容无效")
    secrets = read_secrets_file(secrets_path(stem))
    prev = previous if isinstance(previous, dict) else {}

    cfg_type = str(payload.get("type") or "git").strip().lower()
    is_dir = cfg_type in ("dir", "directory")
    payload["type"] = "dir" if is_dir else "git"

    if is_dir:
        # 目录模式不写 gitee / replace_dir
        payload.pop("gitee", None)
        sync = payload.get("sync")
        if isinstance(sync, dict):
            sync.pop("replace_dir", None)
        dir_block = payload.get("dir")
        if not isinstance(dir_block, dict):
            dir_block = {}
            payload["dir"] = dir_block
        if not str(dir_block.get("source_dir") or "").strip():
            raise ValueError("目录同步需填写 dir.source_dir")
    else:
        gitee = payload.get("gitee")
        if not isinstance(gitee, dict):
            raise ValueError("Git 同步需填写 gitee 配置")
        if gitee.get("auth_type") == "password":
            key = "GITEE_PASSWORD"
            pw = (gitee.get("password") or "").strip()
            prev_ref = ""
            prev_gitee = prev.get("gitee") if isinstance(prev.get("gitee"), dict) else {}
            if prev_gitee.get("auth_type") == "password":
                prev_ref = prev_gitee.get("password") or ""
            if pw:
                secrets[key] = pw
                gitee["password"] = f"secret:{key}"
            elif is_secret_ref(prev_ref):
                gitee["password"] = prev_ref
            elif secrets.get(key):
                gitee["password"] = f"secret:{key}"
            else:
                gitee["password"] = ""
        else:
            gitee.pop("password", None)
        gitee.pop("_password_ref", None)
        gitee.pop("_password_saved", None)

    for gi, group in enumerate(payload.get("server_groups") or []):
        if not isinstance(group, dict):
            continue
        for si, server in enumerate(group.get("servers") or []):
            if not isinstance(server, dict):
                continue
            server.pop("_auth_info_ref", None)
            server.pop("_auth_info_saved", None)
            if server.get("auth_type") != "password":
                continue
            name = server.get("name") or f"server_{gi}_{si}"
            key = f"SERVER_{sanitize_key(name)}"
            val = (server.get("auth_info") or "").strip()
            prev_ref = ""
            try:
                prev_server = (((prev.get("server_groups") or [])[gi].get("servers") or [])[si])
                if isinstance(prev_server, dict):
                    prev_ref = prev_server.get("auth_info") or ""
            except (IndexError, AttributeError, TypeError):
                prev_ref = ""
            if val:
                secrets[key] = val
                server["auth_info"] = f"secret:{key}"
            elif is_secret_ref(prev_ref):
                server["auth_info"] = prev_ref
            elif secrets.get(key):
                server["auth_info"] = f"secret:{key}"
            else:
                server["auth_info"] = ""

    write_secrets_file(secrets_path(stem), secrets)
    return payload


def save_config(name: str, data: dict) -> str:
    safe_name = Path(name).name
    if not safe_name.endswith(".yml"):
        safe_name += ".yml"
    if ".." in safe_name:
        raise ValueError("invalid config name")

    payload = data.get("raw") or data
    if not isinstance(payload, dict):
        raise ValueError("配置内容无效")
    stem = Path(safe_name).stem
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    path = CONFIG_DIR / safe_name
    previous = yaml_load(path) if path.is_file() else {}
    if not isinstance(previous, dict):
        previous = {}
    payload = externalize_secrets(stem, payload, previous)
    yaml_dump(path, payload)
    return safe_name


def sanitize_terminal_output(text: str) -> str:
    """清理管道输出中的 ANSI / 光标控制符 / rsync 进度覆写。"""
    if "\r" in text:
        # rsync --progress 用 \r 原地刷新，只保留最后一次内容
        text = text.split("\r")[-1]
    text = CSI_RE.sub("", text)
    text = OSC_RE.sub("", text)
    text = ANSI_RE.sub("", text)
    text = ORPHAN_CSI_RE.sub("", text)
    text = text.replace("\x08", "").replace("\x07", "")
    return text.strip()


def strip_ansi(text: str) -> str:
    return sanitize_terminal_output(text)


def set_pty_size(fd: int, rows: int = 24, cols: int = 120) -> None:
    """PTY 需有窗口尺寸，git 才会实时刷新 stderr 进度。"""
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except OSError:
        pass


def sync_subprocess_env() -> dict[str, str]:
    env = os.environ.copy()
    # 不能用 TERM=dumb，否则 git 会缓冲/弱化进度输出
    env["TERM"] = "xterm-256color"
    env["GIT_FLUSH"] = "1"
    env["NO_COLOR"] = "1"
    env["CLICOLOR"] = "0"
    env["FORCE_COLOR"] = "0"
    return env


def unbuffered_cmd(cmd: list[str]) -> list[str]:
    """管道模式下尽量行缓冲；macOS 不用 script（会分配 PTY 导致 progress 乱码）。"""
    if HAS_STDBUF:
        return ["stdbuf", "-oL", "-eL", *cmd]
    return cmd


def is_git_inplace_progress(clean: str) -> bool:
    """仅本地 Receiving/Resolving 进度单行刷新（与终端一致）。"""
    if not clean or clean.startswith("Cloning into "):
        return False
    if GIT_PROGRESS_DONE_RE.search(clean):
        return False
    return bool(GIT_LOCAL_PROGRESS_RE.match(clean))


def should_drop_git_line(clean: str) -> bool:
    """丢弃 remote 侧未完成的 \\r 碎片（如 Compressing objec）。"""
    if not clean.startswith("remote:"):
        return False
    if GIT_PROGRESS_DONE_RE.search(clean):
        return False
    return bool(GIT_REMOTE_PROGRESS_RE.match(clean))


def format_sync_line(clean: str) -> dict | None:
    """格式化 sync 流式输出行；git 进度压缩为单行 replace。"""
    if not clean:
        return None
    if should_drop_git_line(clean):
        return None
    if "Permanently added" in clean and "known hosts" in clean.lower():
        return None
    level = "error" if "ERROR" in clean or "失败" in clean else "info"
    payload: dict = {"text": clean, "level": level}
    if is_git_inplace_progress(clean):
        payload["replace"] = "git"
    return payload


def _decode_progress_segment(segment: bytes) -> str:
    return segment.decode("utf-8", errors="replace")


def _emit_local_git_progress(segment: bytes, last_inplace: str) -> tuple[str | None, str]:
    text = _decode_progress_segment(segment)
    if GIT_LOCAL_PROGRESS_RE.match(text) and text != last_inplace:
        return text, text
    return None, last_inplace


def iter_pty_output(master_fd: int, proc: subprocess.Popen):
    """从 PTY 实时读取；\\r\\n 换行；本地 git 下载进度以 \\r 结尾立即刷新。"""
    buf = b""
    last_inplace = ""

    while True:
        proc_done = proc.poll() is not None

        if proc_done:
            while True:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                buf += chunk
        else:
            ready, _, _ = select.select([master_fd], [], [], 0.05)
            if master_fd in ready:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    chunk = b""
                if chunk:
                    buf += chunk

        buf = buf.replace(b"\r\n", b"\n")

        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = _decode_progress_segment(line)
            if text:
                last_inplace = ""
                yield text

        # git 本地进度以 \r 结尾（无 \n），必须立即输出，不能等 proc 结束
        if buf.endswith(b"\r"):
            segment = buf[:-1]
            if b"\r" in segment:
                segment = segment.rsplit(b"\r", 1)[-1]
            text = _decode_progress_segment(segment)
            if GIT_LOCAL_PROGRESS_RE.match(text):
                emitted, last_inplace = _emit_local_git_progress(segment, last_inplace)
                if emitted:
                    yield emitted
                buf = b""
            elif text.startswith("remote:"):
                buf = b""  # 丢弃 remote 侧未完成的 \r 进度碎片
            # 否则保留 buf（可能是 CRLF 分包，如 "banner\r" 等待 \n）

        elif b"\r" in buf:
            segment = buf.rsplit(b"\r", 1)[-1]
            emitted, last_inplace = _emit_local_git_progress(segment, last_inplace)
            if emitted:
                yield emitted
                buf = segment

        if proc_done:
            if buf:
                tail = buf[:-1] if buf.endswith(b"\r") else buf
                if b"\r" in tail:
                    tail = tail.rsplit(b"\r", 1)[-1]
                text = _decode_progress_segment(tail).strip("\r\n")
                if text and text != last_inplace:
                    yield text
            break

class SyncUIHandler(BaseHTTPRequestHandler):
    server_version = "SyncUI/1.0"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8") if length else "{}"
        return json.loads(raw or "{}")

    def _send_file(self, path: Path, content_type: str) -> None:
        if not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        data = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/":
            self._send_file(STATIC_DIR / "index.html", "text/html; charset=utf-8")
            return
        if path.startswith("/static/"):
            rel = path[len("/static/") :]
            target = (STATIC_DIR / rel).resolve()
            if not str(target).startswith(str(STATIC_DIR.resolve())):
                self.send_error(HTTPStatus.FORBIDDEN)
                return
            ctype = "text/css; charset=utf-8" if target.suffix == ".css" else "application/javascript; charset=utf-8"
            self._send_file(target, ctype)
            return
        if path == "/api/configs":
            self._send_json(HTTPStatus.OK, {"configs": list_configs()})
            return
        if path == "/api/config":
            qs = parse_qs(parsed.query)
            name = (qs.get("name") or [""])[0]
            try:
                data = load_config(name)
                self._send_json(HTTPStatus.OK, data)
            except FileNotFoundError:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "config not found"})
            return
        if path == "/api/dir/status":
            qs = parse_qs(parsed.query)
            name = (qs.get("config") or qs.get("config_name") or [""])[0]
            try:
                self._send_json(HTTPStatus.OK, dir_upload_status(name))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/ssh/keys":
            try:
                self._send_json(HTTPStatus.OK, list_ssh_keys())
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/replace/envs":
            qs = parse_qs(parsed.query)
            replace_dir = (qs.get("replace_dir") or [""])[0]
            try:
                self._send_json(HTTPStatus.OK, list_replace_envs(replace_dir))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        if path == "/api/replace/files":
            qs = parse_qs(parsed.query)
            replace_dir = (qs.get("replace_dir") or [""])[0]
            env = (qs.get("env") or [""])[0]
            try:
                self._send_json(HTTPStatus.OK, list_replace_files(replace_dir, env))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        if path == "/api/replace/file":
            qs = parse_qs(parsed.query)
            replace_dir = (qs.get("replace_dir") or [""])[0]
            env = (qs.get("env") or [""])[0]
            rel = (qs.get("path") or [""])[0]
            try:
                self._send_json(HTTPStatus.OK, read_replace_file(replace_dir, env, rel))
            except FileNotFoundError:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "file not found"})
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/config":
            try:
                body = self._read_json()
                name = body.get("config_name") or "untitled"
                saved = save_config(name, body)
                self._send_json(HTTPStatus.OK, {"ok": True, "name": saved})
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/run":
            try:
                body = self._read_json()
                config_name = body.get("config")
                group = str(body.get("group", "1"))
                verbose = bool(body.get("verbose"))
                force = bool(body.get("force"))
                post_sync = str(body.get("post_sync") or "1")
                post_commands = body.get("post_commands")
                if isinstance(post_commands, list):
                    post_commands = [str(c).strip() for c in post_commands if str(c).strip()]
                else:
                    post_commands = None
                if not config_name:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "缺少 config"})
                    return
                self._stream_sync(config_name, group, verbose, force, post_sync, post_commands)
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/replace/env":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    ensure_replace_env(body.get("replace_dir") or "", body.get("env") or ""),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/replace/upload":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    upload_replace_files(
                        body.get("replace_dir") or "",
                        body.get("env") or "",
                        body.get("files") or [],
                        body.get("prefix") or "",
                    ),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/replace/archive":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    extract_replace_archive(
                        body.get("replace_dir") or "",
                        body.get("env") or "",
                        body.get("filename") or "",
                        body.get("content_b64") or "",
                        body.get("prefix") or "",
                    ),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/replace/import":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    import_replace_from_path(
                        body.get("replace_dir") or "",
                        body.get("env") or "",
                        body.get("source_path") or "",
                        body.get("local_dir") or "",
                        body.get("project_name") or "",
                    ),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/dir/status":
            try:
                body = self._read_json()
                self._send_json(HTTPStatus.OK, dir_upload_status(body.get("config") or body.get("config_name") or ""))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/dir/upload":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    upload_dir_files(
                        body.get("config") or body.get("config_name") or "",
                        body.get("files") or [],
                        clear=body.get("clear", True),
                    ),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/dir/archive":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    extract_dir_archive(
                        body.get("config") or body.get("config_name") or "",
                        body.get("filename") or "",
                        body.get("content_b64") or "",
                        clear=body.get("clear", True),
                    ),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/dir/clear":
            try:
                body = self._read_json()
                clear_dir_workdir(body.get("config") or body.get("config_name") or "")
                self._send_json(HTTPStatus.OK, dir_upload_status(body.get("config") or body.get("config_name") or ""))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/ssh/upload":
            try:
                body = self._read_json()
                self._send_json(
                    HTTPStatus.OK,
                    upload_ssh_key(body.get("filename") or body.get("name") or "", body.get("content_b64") or ""),
                )
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path == "/api/ssh/delete":
            try:
                body = self._read_json()
                self._send_json(HTTPStatus.OK, delete_ssh_key(body.get("filename") or body.get("name") or ""))
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if path in ("/api/replace/file", "/api/replace/delete"):
            try:
                body = self._read_json()
                action = (body.get("action") or "").lower()
                if path.endswith("/delete") and not action:
                    action = "delete_batch"
                if not action:
                    action = "save"
                replace_dir = body.get("replace_dir") or ""
                env = body.get("env") or ""

                if action in ("delete_batch", "batch_delete"):
                    paths = list(body.get("paths") or [])
                    dirs = list(body.get("dirs") or [])
                    if not paths and not dirs and body.get("path"):
                        paths = [body.get("path")]
                    self._send_json(
                        HTTPStatus.OK,
                        delete_replace_batch(replace_dir, env, paths, dirs),
                    )
                elif action == "delete":
                    self._send_json(
                        HTTPStatus.OK,
                        delete_replace_file(replace_dir, env, body.get("path") or ""),
                    )
                else:
                    self._send_json(
                        HTTPStatus.OK,
                        write_replace_file(
                            replace_dir, env, body.get("path") or "", body.get("content") or ""
                        ),
                    )
            except FileNotFoundError:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "file not found"})
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": f"not found: {path}"})

    def _stream_sync(
        self,
        config_name: str,
        group: str,
        verbose: bool,
        force: bool,
        post_sync: str = "1",
        post_commands: list[str] | None = None,
    ) -> None:
        sync_sh = PROJECT_ROOT / "sync.sh"
        inner = [str(sync_sh), f"--config={config_name}", f"--group={group}", "-y"]
        if verbose:
            inner.append("-v")
        if force:
            inner.append("-f")

        mode = post_sync.strip().lower()
        if mode in ("1", "all", "2", "ask", "3", "skip"):
            inner.append(f"--post-sync={mode}")
        else:
            inner.append("--post-sync=1")

        cmd_file = None
        if post_commands is not None:
            # 空列表 = 跳过；非空 = 只执行勾选的命令
            if not post_commands:
                # 覆盖为 skip
                inner = [c for c in inner if not c.startswith("--post-sync=")]
                inner.append("--post-sync=3")
            else:
                cmd_file = Path(f"/tmp/sync-ui-post-cmds-{os.getpid()}.txt")
                cmd_file.write_text("\n".join(post_commands) + "\n", encoding="utf-8")
                inner.append(f"--post-commands-file={cmd_file}")

        cmd = inner

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        def write_event(event: str, data: dict) -> None:
            payload = json.dumps(data, ensure_ascii=False)
            chunk = f"event: {event}\ndata: {payload}\n\n".encode("utf-8")
            self.wfile.write(chunk)
            self.wfile.flush()

        write_event("meta", {"cmd": " ".join(cmd)})

        master_fd: int | None = None
        try:
            master_fd, slave_fd = pty.openpty()
            set_pty_size(slave_fd)
            proc = subprocess.Popen(
                cmd,
                cwd=str(PROJECT_ROOT),
                stdout=slave_fd,
                stderr=slave_fd,
                env=sync_subprocess_env(),
                close_fds=True,
            )
            os.close(slave_fd)
            set_pty_size(master_fd)
        except OSError as exc:
            if master_fd is not None:
                os.close(master_fd)
            write_event("line", {"text": f"启动失败: {exc}", "level": "error"})
            write_event("done", {"code": 1})
            if cmd_file and cmd_file.exists():
                cmd_file.unlink(missing_ok=True)
            return

        try:
            for raw in iter_pty_output(master_fd, proc):
                clean = sanitize_terminal_output(raw.rstrip("\r\n"))
                payload = format_sync_line(clean)
                if payload:
                    write_event("line", payload)

            code = proc.wait()
            write_event("done", {"code": code})
        finally:
            if master_fd is not None:
                os.close(master_fd)
            if cmd_file and cmd_file.exists():
                cmd_file.unlink(missing_ok=True)


def main() -> None:
    ensure_yaml_backend()
    port = int(os.environ.get("SYNC_UI_PORT", DEFAULT_PORT))
    host = os.environ.get("SYNC_UI_HOST", "127.0.0.1")
    open_browser = os.environ.get("SYNC_UI_NO_BROWSER", "").strip() not in ("1", "true", "yes")
    server = ThreadingHTTPServer((host, port), SyncUIHandler)
    url = f"http://{host}:{port}/"
    print(f"Sync UI 已启动: {url}")
    print("按 Ctrl+C 停止")

    if open_browser and host in ("127.0.0.1", "localhost"):
        threading.Timer(0.8, lambda: webbrowser.open(f"http://127.0.0.1:{port}/")).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
        server.server_close()


if __name__ == "__main__":
    main()
