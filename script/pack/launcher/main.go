// GitShip 单文件启动器：解压 → 环境检查 → 引导安装 → 启动 UI / sync。
package main

import (
	"archive/tar"
	"compress/gzip"
	"embed"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

//go:embed payload.tar.gz
var payloadFS embed.FS

// 构建时注入：-ldflags "-X main.Version=1.0.0"
var Version = "dev"

func main() {
	home, err := appHome()
	if err != nil {
		fatal(err)
	}
	if err := ensureExtracted(home); err != nil {
		fatal(err)
	}
	if err := os.Chdir(home); err != nil {
		fatal(err)
	}

	args := os.Args[1:]
	mode := "ui"
	if len(args) > 0 {
		switch args[0] {
		case "ui", "sync", "check", "doctor", "help", "-h", "--help":
			mode = args[0]
			args = args[1:]
		default:
			mode = "sync"
		}
	}
	if mode == "help" || mode == "-h" || mode == "--help" {
		printHelp()
		return
	}
	if mode == "check" || mode == "doctor" {
		deps := checkEnvironment("all")
		printEnvReport(deps)
		miss := missingRequired("all", deps)
		if len(miss) > 0 {
			guideInstall(miss)
			pauseExit(1)
		}
		fmt.Println("环境检查通过。")
		if runtime.GOOS == "windows" {
			waitEnter("按回车键退出…")
		}
		return
	}

	// 1) 检查环境  2) 引导安装  3) 启动
	checkMode := mode
	if checkMode != "sync" {
		checkMode = "ui"
	}
	if err := ensureReady(checkMode); err != nil {
		fatal(err)
	}

	switch mode {
	case "ui":
		fmt.Println("[gitship] 环境就绪，正在启动界面…")
		if err := runUI(); err != nil {
			fatal(err)
		}
	case "sync":
		if err := runSync(args); err != nil {
			fatal(err)
		}
	default:
		fatal(fmt.Errorf("unknown mode: %s", mode))
	}
}

func ensureReady(mode string) error {
	deps := checkEnvironment(mode)
	printEnvReport(deps)
	miss := missingRequired(mode, deps)
	if len(miss) == 0 {
		return nil
	}
	guideInstall(miss)
	// 弱引导：只提示一次，不自动循环重试 / 不强开浏览器
	if runtime.GOOS == "windows" {
		waitEnter("按回车键退出；安装好依赖后请重新运行 gitship.exe…")
		os.Exit(1)
	}
	waitEnter("")
	deps = checkEnvironment(mode)
	printEnvReport(deps)
	miss = missingRequired(mode, deps)
	if len(miss) > 0 {
		return fmt.Errorf("环境仍不完整，请安装后重试")
	}
	return nil
}

func printHelp() {
	fmt.Printf(`gitship %s

用法:
  gitship              检查环境后打开配置界面
  gitship ui
  gitship check        仅检查本机依赖（doctor）
  gitship sync [args]  执行同步（需 bash/git/rsync）

默认安装/数据目录:
  %s

环境变量:
  GITSHIP_HOME      覆盖数据目录
  GITSHIP_PORTABLE=1  改用可执行文件旁 gitship-home（便携模式）

Windows 提示:
  退出码 9009 = 找不到命令（多为未装 Python，或只有微软商店占位符）
  安装 Python 时务必勾选 Add to PATH，然后重新打开本程序
`, Version, mustHome())
}

func mustHome() string {
	h, _ := appHome()
	return h
}

func envFirst(keys ...string) string {
	for _, k := range keys {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	return ""
}

func appHome() (string, error) {
	if v := envFirst("GITSHIP_HOME", "PHP_DEPLOY_HOME"); v != "" {
		return filepath.Abs(v)
	}
	if envFirst("GITSHIP_PORTABLE", "PHP_DEPLOY_PORTABLE") == "1" {
		exe, err := os.Executable()
		if err != nil {
			return "", err
		}
		exe, err = filepath.EvalSymlinks(exe)
		if err != nil {
			return "", err
		}
		return filepath.Join(filepath.Dir(exe), "gitship-home"), nil
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "gitship"), nil
}

func ensureExtracted(home string) error {
	wantVer := strings.TrimSpace(Version)
	wantID, _ := readPayloadFile(".payload-id")
	wantID = strings.TrimSpace(wantID)

	curVer := ""
	if b, err := os.ReadFile(filepath.Join(home, "VERSION")); err == nil {
		curVer = strings.TrimSpace(string(b))
	}
	curID := ""
	if b, err := os.ReadFile(filepath.Join(home, ".payload-id")); err == nil {
		curID = strings.TrimSpace(string(b))
	}

	same := curVer != "" && curVer == wantVer
	if wantID != "" {
		same = same && curID == wantID
	}
	if same {
		return nil
	}

	if err := os.MkdirAll(home, 0o755); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "[gitship] 安装/更新 v%s → %s\n", Version, home)
	f, err := payloadFS.Open("payload.tar.gz")
	if err != nil {
		return err
	}
	defer f.Close()
	return extractTarGz(f, home)
}

func readPayloadFile(name string) (string, error) {
	f, err := payloadFS.Open("payload.tar.gz")
	if err != nil {
		return "", err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return "", err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}
		n := hdr.Name
		n = strings.TrimPrefix(n, "./")
		if i := strings.IndexByte(n, '/'); i >= 0 {
			n = n[i+1:]
		}
		if n == name && (hdr.Typeflag == tar.TypeReg || hdr.Typeflag == tar.TypeRegA) {
			b, err := io.ReadAll(tr)
			if err != nil {
				return "", err
			}
			return string(b), nil
		}
	}
	return "", os.ErrNotExist
}

func extractTarGz(r io.Reader, dest string) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		name := hdr.Name
		name = strings.TrimPrefix(name, "./")
		if i := strings.IndexByte(name, '/'); i >= 0 {
			name = name[i+1:]
		} else {
			continue
		}
		if name == "" || strings.Contains(name, "..") {
			continue
		}
		target := filepath.Join(dest, filepath.FromSlash(name))
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, os.FileMode(hdr.Mode)|0o644)
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return err
			}
			out.Close()
		}
	}
	return nil
}

func runUI() error {
	py := findPython()
	if py == "" {
		return fmt.Errorf("未找到 python/python3，请先安装 Python 3（exit 9009 多为命令不存在）")
	}
	exe, pre := pythonCmd(py)
	entry := filepath.Join("script", "sync-ui", "desktop.py")
	if _, err := os.Stat(entry); err != nil {
		entry = filepath.Join("script", "sync-ui", "app.py")
	}
	args := append(append([]string{}, pre...), entry)
	cmd := exec.Command(exe, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	env := os.Environ()
	if os.Getenv("SYNC_UI_HOST") == "" {
		env = append(env, "SYNC_UI_HOST=127.0.0.1")
	}
	env = append(env, "SYNC_UI_NO_BROWSER=1")
	cmd.Env = env
	hideConsole(cmd)
	return cmd.Run()
}

func runSync(args []string) error {
	bash := findBash()
	if bash == "" {
		return fmt.Errorf("未找到 bash（Windows 请安装 Git for Windows）")
	}
	cmdArgs := append([]string{"sync.sh"}, args...)
	cmd := exec.Command(bash, cmdArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func findBash() string {
	if p, err := exec.LookPath("bash"); err == nil {
		return p
	}
	if runtime.GOOS == "windows" {
		candidates := []string{
			`C:\Program Files\Git\bin\bash.exe`,
			`C:\Program Files (x86)\Git\bin\bash.exe`,
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				return c
			}
		}
	}
	return ""
}

func fatal(err error) {
	fmt.Fprintf(os.Stderr, "[gitship] %v\n", err)
	pauseExit(1)
}
