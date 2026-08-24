// Package nix 封装所有 nix 命令调用与输出解析。
// 所有命令均以参数数组方式构造（无 shell 拼接），由调用方做输入校验。
package nix

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// SystemProfile 是系统 generation 的 profile 路径。
const SystemProfile = "/nix/var/nix/profiles/system"

// Hostname 返回主机名（flake 主机名，失败时回退 reimilia）。
func Hostname() string {
	h, err := os.Hostname()
	if err != nil || h == "" {
		return "reimilia"
	}
	return h
}

// ---------- 命令构造 ----------

// RebuildCmd 重建系统：nixos-rebuild switch --flake <dir>#<host>。
func RebuildCmd(configDir string) *exec.Cmd {
	return exec.Command("nixos-rebuild", "switch", "--flake", configDir+"#"+Hostname())
}

// FlakeUpdateCmd 更新所有 flake 输入（在配置目录内执行）。
func FlakeUpdateCmd(dir string) *exec.Cmd {
	c := exec.Command("nix", "flake", "update")
	c.Dir = dir
	return c
}

// GcCmd 清理构建垃圾（删除旧 generation 与无用 store 路径）。
func GcCmd() *exec.Cmd {
	return exec.Command("nix-collect-garbage", "-d")
}

// ListGenerationsCmd 列出系统 generations。
func ListGenerationsCmd() *exec.Cmd {
	return exec.Command("nix-env", "--list-generations", "-p", SystemProfile)
}

// SwitchGenerationCmd 切换到指定 generation（-1 = 上一个版本）。
func SwitchGenerationCmd(gen int) *exec.Cmd {
	return exec.Command("nix-env", "--switch-generation", strconv.Itoa(gen), "-p", SystemProfile)
}

// SwitchToConfigCmd 激活当前 profile 指向的 generation。
func SwitchToConfigCmd() *exec.Cmd {
	return exec.Command("/run/current-system/bin/switch-to-configuration", "switch")
}

// SearchCmd 在 nixpkgs 中搜索包（--json 输出）。
func SearchCmd(query string) *exec.Cmd {
	return exec.Command("nix", "search", "nixpkgs", "--json", query)
}

// EvalCmd 校验包属性是否存在：nix eval --raw nixpkgs#<attr>。
func EvalCmd(attr string) *exec.Cmd {
	return exec.Command("nix", "eval", "--raw", "nixpkgs#"+attr)
}

// ProfileListCmd 列出当前用户的 nix profile（临时安装的包）。
func ProfileListCmd() *exec.Cmd {
	return exec.Command("nix", "profile", "list")
}

// ProfileInstallCmd 临时安装包到当前用户 profile。
func ProfileInstallCmd(attr string) *exec.Cmd {
	return exec.Command("nix", "profile", "install", "nixpkgs#"+attr)
}

// ProfileRemoveCmd 从 profile 移除指定索引的包。
func ProfileRemoveCmd(index string) *exec.Cmd {
	return exec.Command("nix", "profile", "remove", index)
}

// JournalCmd 查看系统日志（当前启动 -b）。
func JournalCmd(unit, lines string, follow bool) *exec.Cmd {
	args := []string{"-b", "-n", lines, "-o", "short"}
	if unit != "" {
		args = append(args, "-u", unit)
	}
	if follow {
		args = append(args, "-f")
	}
	return exec.Command("journalctl", args...)
}

// ListUnitsCmd 列出所有服务 unit。
func ListUnitsCmd() *exec.Cmd {
	return exec.Command("systemctl", "list-units", "--type=service", "--no-pager", "--no-legend")
}

// ---------- 简单只读查询 ----------

// runOutput 执行命令并在超时内取回输出（失败返回空串）。
func runOutput(timeout time.Duration, name string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// Generation 是一个系统 generation。
type Generation struct {
	N       int    `json:"n"`
	Date    string `json:"date"`
	Current bool   `json:"current"`
}

// ListGenerations 解析 nix-env --list-generations 输出。
func ListGenerations() ([]Generation, error) {
	out, err := exec.Command("nix-env", "--list-generations", "-p", SystemProfile).CombinedOutput()
	if err != nil {
		return nil, err
	}
	var gens []Generation
	for _, ln := range strings.Split(string(out), "\n") {
		fields := strings.Fields(ln)
		if len(fields) < 2 {
			continue
		}
		n, err := strconv.Atoi(fields[0])
		if err != nil {
			continue
		}
		g := Generation{N: n, Date: fields[1] + " " + fields[2]}
		g.Current = strings.Contains(ln, "(current)")
		gens = append(gens, g)
	}
	return gens, nil
}

// CurrentGeneration 返回当前 generation 号（-1 表示未知）。
func CurrentGeneration() int {
	gens, err := ListGenerations()
	if err != nil {
		return -1
	}
	for _, g := range gens {
		if g.Current {
			return g.N
		}
	}
	if len(gens) > 0 {
		return gens[len(gens)-1].N
	}
	return -1
}

// SearchResult 是一个 nix search 结果。
type SearchResult struct {
	Attr        string `json:"attr"`
	Pname       string `json:"pname"`
	Version     string `json:"version"`
	Description string `json:"description"`
}

// ParseSearchJSON 解析 `nix search nixpkgs --json` 输出。
func ParseSearchJSON(data []byte) []SearchResult {
	var raw map[string]struct {
		Pname       string `json:"pname"`
		Version     string `json:"version"`
		Description string `json:"description"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil
	}
	platform := runtime.GOARCH
	if platform == "amd64" {
		platform = "x86_64"
	}
	prefixes := []string{
		"legacyPackages." + runtime.GOOS + "-" + platform + ".",
		"packages." + runtime.GOOS + "-" + platform + ".",
		"legacyPackages." + platform + "-" + runtime.GOOS + ".",
	}
	var out []SearchResult
	for key, v := range raw {
		attr := ""
		for _, p := range prefixes {
			if strings.HasPrefix(key, p) {
				attr = strings.TrimPrefix(key, p)
				break
			}
		}
		if attr == "" || attr == key {
			continue
		}
		out = append(out, SearchResult{Attr: attr, Pname: v.Pname, Version: v.Version, Description: v.Description})
	}
	if len(out) > 50 {
		out = out[:50]
	}
	return out
}

// ProfileEntry 是 nix profile list 里的一项。
type ProfileEntry struct {
	Index     string `json:"index"`
	Name      string `json:"name"`
	StorePath string `json:"storePath"`
}

// ListProfile 解析 `nix profile list`。
func ListProfile() ([]ProfileEntry, error) {
	out, err := exec.Command("nix", "profile", "list").CombinedOutput()
	if err != nil {
		return nil, err
	}
	var entries []ProfileEntry
	for _, ln := range strings.Split(string(out), "\n") {
		fields := strings.Fields(ln)
		if len(fields) < 2 {
			continue
		}
		entries = append(entries, ProfileEntry{Index: fields[0], Name: fields[1], StorePath: ""})
	}
	return entries, nil
}

// SystemStatus 是概览页的状态信息。
type SystemStatus struct {
	Hostname      string `json:"hostname"`
	OS            string `json:"os"`
	Uptime        string `json:"uptime"`
	Generation    int    `json:"generation"`
	RunningSystem string `json:"runningSystem"`
	NixVersion    string `json:"nixVersion"`
	Disk          string `json:"disk"`
	StoreSize     string `json:"storeSize"`
	ConfigDir     string `json:"configDir"`
	HasFlake      bool   `json:"hasFlake"`
}

// GetStatus 收集系统状态。
func GetStatus(configDir string) SystemStatus {
	st := SystemStatus{
		Hostname:      Hostname(),
		OS:            osRelease("PRETTY_NAME"),
		Uptime:        readUptime(),
		Generation:    CurrentGeneration(),
		RunningSystem: readlinkOr("", "/run/current-system"),
		NixVersion:    runOutput(10*time.Second, "nix", "--version"),
		Disk:          runOutput(5*time.Second, "df", "-h", "/"),
		StoreSize:     runOutput(20*time.Second, "du", "-sh", "/nix/store"),
		ConfigDir:     configDir,
	}
	if _, err := os.Stat(configDir + "/flake.nix"); err == nil {
		st.HasFlake = true
	}
	return st
}

func readlinkOr(def, path string) string {
	v, err := os.Readlink(path)
	if err != nil {
		return def
	}
	return v
}

func readUptime() string {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return ""
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return ""
	}
	d := int(secs) / 86400
	h := int(secs) % 86400 / 3600
	m := int(secs) % 3600 / 60
	return strconv.Itoa(d) + "天 " + strconv.Itoa(h) + "小时 " + strconv.Itoa(m) + "分"
}

func osRelease(key string) string {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return ""
	}
	for _, ln := range strings.Split(string(data), "\n") {
		if k, v, ok := strings.Cut(ln, "="); ok && k == key {
			return strings.Trim(strings.TrimSpace(v), `"`)
		}
	}
	return ""
}
