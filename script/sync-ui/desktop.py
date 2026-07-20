#!/usr/bin/env python3
"""桌面窗口模式：启动本地 UI，优先原生窗口（pywebview），否则 Chrome/Edge App 模式。"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import ThreadingHTTPServer

# 保证可导入同目录 app
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import app as sync_ui  # noqa: E402


def wait_port(host: str, port: int, timeout: float = 8.0) -> bool:
    import socket

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=0.3):
                return True
        except OSError:
            time.sleep(0.15)
    return False


def open_chrome_app(url: str) -> bool:
    """用系统浏览器的 --app 模式弹出独立窗口（无需重写前端）。"""
    candidates: list[list[str]] = []
    if sys.platform == "darwin":
        for app in (
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
        ):
            if os.path.isfile(app):
                candidates.append([app, f"--app={url}"])
        # open -na 备选
        candidates.append(["open", "-na", "Google Chrome", "--args", f"--app={url}"])
    elif sys.platform.startswith("win"):
        local = os.environ.get("LOCALAPPDATA", "")
        pf = os.environ.get("PROGRAMFILES", r"C:\Program Files")
        pf86 = os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)")
        for path in (
            os.path.join(local, "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(local, "Microsoft", "Edge", "Application", "msedge.exe"),
            os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
            os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
        ):
            if os.path.isfile(path):
                candidates.append([path, f"--app={url}"])
    else:
        for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge"):
            p = shutil.which(name)
            if p:
                candidates.append([p, f"--app={url}"])

    for cmd in candidates:
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except OSError:
            continue
    return False


def run_webview(url: str) -> bool:
    try:
        import webview  # type: ignore
    except ImportError:
        return False
    webview.create_window("GitShip", url, width=1280, height=860, min_size=(900, 600))
    webview.start()
    return True


def main() -> None:
    sync_ui.ensure_yaml_backend()
    port = int(os.environ.get("SYNC_UI_PORT", sync_ui.DEFAULT_PORT))
    host = os.environ.get("SYNC_UI_HOST", "127.0.0.1")
    # 桌面模式由本进程负责开窗，禁止再弹系统浏览器标签页
    os.environ["SYNC_UI_NO_BROWSER"] = "1"

    server = ThreadingHTTPServer((host, port), sync_ui.SyncUIHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    url = f"http://127.0.0.1:{port}/"
    if not wait_port("127.0.0.1", port):
        print("UI 服务启动超时", file=sys.stderr)
        server.shutdown()
        sys.exit(1)

    print(f"Sync UI 桌面模式: {url}")

    # 1) pywebview 原生窗  2) Chrome/Edge --app=  3) 系统默认浏览器
    if run_webview(url):
        server.shutdown()
        return

    if open_chrome_app(url):
        print("已用浏览器 App 模式打开独立窗口（可选: pip install pywebview 获得原生窗）")
        try:
            while thread.is_alive():
                time.sleep(0.5)
        except KeyboardInterrupt:
            pass
        finally:
            server.shutdown()
        return

    webbrowser.open(url)
    print("已在默认浏览器打开（建议安装 Chrome/Edge 或 pip install pywebview）")
    try:
        while thread.is_alive():
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
