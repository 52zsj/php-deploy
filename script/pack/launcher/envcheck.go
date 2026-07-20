package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type depStatus struct {
	Name    string
	OK      bool
	Detail  string
	Hint    string
	Install []string // 可复制的安装命令
	URL     string   // 可选下载页
}

func checkEnvironment(mode string) []depStatus {
	var out []depStatus
	out = append(out, checkPython())
	if mode == "sync" || mode == "all" {
		out = append(out, checkBash(), checkGit(), checkRsync())
	}
	// UI 也提示同步依赖（不强制）
	if mode == "ui" {
		for _, d := range []depStatus{checkBash(), checkGit(), checkRsync()} {
			d.Name = d.Name + "（同步时需要）"
			out = append(out, d)
		}
	}
	return out
}

func missingRequired(mode string, deps []depStatus) []depStatus {
	var miss []depStatus
	for _, d := range deps {
		if d.OK {
			continue
		}
		name := d.Name
		// UI 模式只强制 Python；check/all/sync 强制全部硬依赖
		if mode == "ui" {
			if !strings.HasPrefix(name, "Python") {
				continue
			}
		} else {
			// 跳过报告里的「同步时需要」可选行（仅 ui 报告会出现）
			if strings.Contains(name, "同步时需要") {
				continue
			}
		}
		miss = append(miss, d)
	}
	return miss
}

func checkPython() depStatus {
	d := depStatus{
		Name: "Python 3",
		URL:  "https://www.python.org/downloads/",
	}
	switch runtime.GOOS {
	case "windows":
		d.Install = []string{
			`winget install -e --id Python.Python.3.12`,
			`# 安装时勾选 “Add python.exe to PATH”，然后重新打开 gitship`,
			`python -m pip install pyyaml`,
		}
		d.Hint = "Windows 退出码 9009 通常表示找不到 python（或只有微软商店占位符）"
	case "darwin":
		d.Install = []string{
			`brew install python`,
			`pip3 install pyyaml`,
		}
	default:
		d.Install = []string{
			`sudo apt install -y python3 python3-pip python3-yaml   # Debian/Ubuntu`,
			`sudo dnf install -y python3 python3-pyyaml            # Fedora`,
		}
	}

	py := findPython()
	if py == "" {
		d.OK = false
		d.Detail = "未找到可用的 Python 3"
		return d
	}
	exe, pre := pythonCmd(py)
	args := append(append([]string{}, pre...), "--version")
	ver := runOut(exe, args...)
	if ver == "" {
		ver = "unknown"
	}
	yamlArgs := append(append([]string{}, pre...), "-c", "import yaml")
	hasYaml := runOK(exe, yamlArgs...)
	d.OK = true
	d.Detail = fmt.Sprintf("%s (%s)", displayPython(py), strings.TrimSpace(ver))
	if !hasYaml {
		d.Detail += "；未安装 PyYAML（建议: python -m pip install pyyaml）"
	}
	return d
}

func displayPython(py string) string {
	exe, pre := pythonCmd(py)
	if len(pre) > 0 {
		return exe + " " + strings.Join(pre, " ")
	}
	return exe
}

func checkBash() depStatus {
	d := depStatus{Name: "Bash"}
	switch runtime.GOOS {
	case "windows":
		d.URL = "https://git-scm.com/download/win"
		d.Install = []string{`winget install -e --id Git.Git`}
		d.Hint = "安装 Git for Windows 后即可使用其自带 bash"
	case "darwin":
		d.Install = []string{`# macOS 自带 bash；或 brew install bash`}
	default:
		d.Install = []string{`sudo apt install -y bash`}
	}
	b := findBash()
	if b == "" {
		d.OK = false
		d.Detail = "未找到 bash"
		return d
	}
	d.OK = true
	d.Detail = b
	return d
}

func checkGit() depStatus {
	d := depStatus{Name: "Git"}
	switch runtime.GOOS {
	case "windows":
		d.URL = "https://git-scm.com/download/win"
		d.Install = []string{`winget install -e --id Git.Git`}
	case "darwin":
		d.Install = []string{`xcode-select --install`, `brew install git`}
	default:
		d.Install = []string{`sudo apt install -y git`}
	}
	p, err := exec.LookPath("git")
	if err != nil {
		// Git for Windows 常见路径
		if runtime.GOOS == "windows" {
			for _, c := range []string{
				`C:\Program Files\Git\cmd\git.exe`,
				`C:\Program Files (x86)\Git\cmd\git.exe`,
			} {
				if _, err := os.Stat(c); err == nil {
					d.OK = true
					d.Detail = c
					return d
				}
			}
		}
		d.OK = false
		d.Detail = "未找到 git"
		return d
	}
	d.OK = true
	d.Detail = fmt.Sprintf("%s (%s)", p, strings.TrimSpace(runOut(p, "--version")))
	return d
}

func checkRsync() depStatus {
	d := depStatus{Name: "rsync"}
	switch runtime.GOOS {
	case "windows":
		d.Hint = "Git Bash 默认不含 rsync；可用 WSL，或安装 cwRsync"
		d.Install = []string{
			`wsl --install`,
			`# 或在 WSL 内: sudo apt install -y rsync`,
		}
		d.URL = "https://learn.microsoft.com/windows/wsl/install"
	case "darwin":
		d.Install = []string{`brew install rsync`}
	default:
		d.Install = []string{`sudo apt install -y rsync`}
	}
	p, err := exec.LookPath("rsync")
	if err != nil {
		d.OK = false
		d.Detail = "未找到 rsync"
		return d
	}
	d.OK = true
	d.Detail = p
	return d
}

func printEnvReport(deps []depStatus) {
	fmt.Println()
	fmt.Println("════════ GitShip 环境检查 ════════")
	for _, d := range deps {
		mark := "✗"
		if d.OK {
			mark = "✓"
		}
		fmt.Printf("  [%s] %-22s %s\n", mark, d.Name, d.Detail)
		if !d.OK && d.Hint != "" {
			fmt.Printf("       提示: %s\n", d.Hint)
		}
	}
	fmt.Println("══════════════════════════════════")
	fmt.Println()
}

func guideInstall(missing []depStatus) {
	fmt.Println("缺少必要环境，请按下面引导安装：")
	fmt.Println()
	for i, d := range missing {
		fmt.Printf("%d) %s\n", i+1, d.Name)
		if d.Hint != "" {
			fmt.Printf("   %s\n", d.Hint)
		}
		for _, line := range d.Install {
			fmt.Printf("   %s\n", line)
		}
		if d.URL != "" {
			fmt.Printf("   下载页: %s\n", d.URL)
		}
		fmt.Println()
	}
}

func waitEnter(msg string) {
	if msg == "" {
		msg = "安装完成后按回车键继续检查（或 Ctrl+C 退出）…"
	}
	fmt.Println(msg)
	_, _ = bufio.NewReader(os.Stdin).ReadBytes('\n')
}

func pauseExit(code int) {
	if runtime.GOOS == "windows" {
		fmt.Println()
		fmt.Print("按回车键退出…")
		_, _ = bufio.NewReader(os.Stdin).ReadBytes('\n')
	} else {
		time.Sleep(2 * time.Second)
	}
	os.Exit(code)
}

func runOK(name string, args ...string) bool {
	cmd := exec.Command(name, args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run() == nil
}

func runOut(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return ""
	}
	return string(out)
}

// findPython 寻找真实 Python，跳过 Windows Store 占位符（常导致退出码 9009）
func findPython() string {
	var candidates []string
	if runtime.GOOS == "windows" {
		if p, err := exec.LookPath("py"); err == nil && !isWindowsStoreStub(p) {
			if runOK(p, "-3", "-c", "import sys; assert sys.version_info >= (3, 8)") {
				return p + "|-3"
			}
		}
		candidates = []string{"python3", "python"}
		local := os.Getenv("LOCALAPPDATA")
		pf := os.Getenv("ProgramFiles")
		for _, base := range []string{
			filepath.Join(local, "Programs", "Python"),
			filepath.Join(pf, "Python312"),
			filepath.Join(pf, "Python311"),
			filepath.Join(pf, "Python310"),
		} {
			entries, err := os.ReadDir(base)
			if err != nil {
				continue
			}
			for _, e := range entries {
				if !e.IsDir() {
					continue
				}
				exe := filepath.Join(base, e.Name(), "python.exe")
				if _, err := os.Stat(exe); err == nil {
					candidates = append(candidates, exe)
				}
			}
			// base 本身可能就是 Python3x 目录
			exe := filepath.Join(base, "python.exe")
			if _, err := os.Stat(exe); err == nil {
				candidates = append(candidates, exe)
			}
		}
	} else {
		candidates = []string{"python3", "python"}
	}

	for _, c := range candidates {
		p := c
		if !filepath.IsAbs(p) {
			found, err := exec.LookPath(p)
			if err != nil {
				continue
			}
			p = found
		}
		if isWindowsStoreStub(p) {
			continue
		}
		if _, err := os.Stat(p); err != nil {
			continue
		}
		if runOK(p, "-c", "import sys; assert sys.version_info >= (3, 8)") {
			return p
		}
	}
	return ""
}

func isWindowsStoreStub(p string) bool {
	low := strings.ToLower(filepath.Clean(p))
	return strings.Contains(low, `\windowsapps\`) || strings.Contains(low, "/windowsapps/")
}

func pythonCmd(py string) (string, []string) {
	if strings.Contains(py, "|") {
		parts := strings.SplitN(py, "|", 2)
		return parts[0], []string{parts[1]}
	}
	return py, nil
}
