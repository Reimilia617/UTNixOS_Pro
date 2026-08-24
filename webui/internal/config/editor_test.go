package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// setup 把仓库真实的 configuration.nix / home-manager.nix / modules 复制到临时目录。
func setup(t *testing.T) *Editor {
	t.Helper()
	repo := filepath.Join("..", "..", "..") // webui/internal/config -> 仓库根
	dir := t.TempDir()
	copyTree(t, repo, dir, "modules")
	for _, f := range []string{"configuration.nix", "home/home-manager.nix"} {
		copyFile(t, repo, dir, f)
	}
	e, err := NewEditor(dir)
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func copyFile(t *testing.T, repo, dir, rel string) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repo, rel))
	if err != nil {
		t.Fatalf("读取 %s 失败: %v", rel, err)
	}
	dst := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func copyTree(t *testing.T, repo, dir, rel string) {
	t.Helper()
	src := filepath.Join(repo, rel)
	err := filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relPath, err := filepath.Rel(repo, path)
		if err != nil {
			return err
		}
		if d.IsDir() {
			return os.MkdirAll(filepath.Join(dir, relPath), 0o755)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(filepath.Join(dir, relPath), data, 0o644)
	})
	if err != nil {
		t.Fatalf("复制 %s 失败: %v", rel, err)
	}
}

func TestModuleEnabledInitial(t *testing.T) {
	e := setup(t)
	cases := map[string]bool{
		"system/clean.nix":       true,
		"system/auto-update.nix": true,
		"system/webui.nix":       false,
		"system/secrets.nix":     false,
		"desktop/xfce.nix":       true,
		"desktop/kde.nix":        false,
		"boot/grub.nix":          true,
		"boot/grub-theme.nix":    true,
		"boot/systemd-boot.nix":  false,
	}
	for mod, want := range cases {
		if got := e.ModuleEnabled(mod); got != want {
			t.Errorf("ModuleEnabled(%q) = %v, want %v", mod, got, want)
		}
	}
}

func TestApplySelection(t *testing.T) {
	e := setup(t)

	st := DefaultState()
	st.Desktop = "kde"
	st.Boot = "systemd-boot"
	st.Locale = "zh_CN"
	st.Input = "fcitx5"
	st.Mirror = "tuna"
	st.UserShell = "fish"
	st.SystemModules = []string{"auto-update", "clean", "nix-command", "zram", "fonts", "webui"}
	st.Advanced = []string{"secrets", "backup"}

	changed, err := e.Apply(st)
	if err != nil {
		t.Fatalf("Apply: %v", err)
	}
	if len(changed) == 0 {
		t.Fatal("Apply 没有返回修改摘要")
	}

	// 验证单选切换
	checks := map[string]bool{
		"desktop/xfce.nix":        false,
		"desktop/kde.nix":         true,
		"boot/grub.nix":           false,
		"boot/grub-theme.nix":     false,
		"boot/systemd-boot.nix":   true,
		"locale/zh_CN.nix":        true,
		"locale/en_US.nix":        false,
		"input/fcitx5.nix":        true,
		"mirrors/tuna.nix":        true,
		"system/webui.nix":        true,
		"system/secrets.nix":      true,
		"system/backup.nix":       true,
		"system/impermanence.nix": false,
		"system/security.nix":     false,
	}
	for mod, want := range checks {
		if got := e.ModuleEnabled(mod); got != want {
			t.Errorf("apply 后 ModuleEnabled(%q) = %v, want %v", mod, got, want)
		}
	}

	// home-manager shell 同步（按行精确检查注释状态）
	hm, err := os.ReadFile(e.dir + "/home/home-manager.nix")
	if err != nil {
		t.Fatal(err)
	}
	shellStates := map[string]bool{} // name -> 是否启用
	for _, ln := range strings.Split(string(hm), "\n") {
		trimmed := strings.TrimSpace(ln)
		commented := strings.HasPrefix(trimmed, "#")
		body := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
		if !strings.HasPrefix(body, "./shell/") {
			continue
		}
		name := strings.TrimPrefix(strings.SplitN(body, " ", 2)[0], "./shell/")
		name = strings.TrimSuffix(name, ".nix")
		shellStates[name] = !commented
	}
	if !shellStates["fish"] {
		t.Errorf("home-manager.nix 中 fish 未启用:\n%s", hm)
	}
	if shellStates["zsh"] || shellStates["bash"] {
		t.Errorf("home-manager.nix 中 zsh/bash 未注释:\n%s", hm)
	}

	// 状态文件回读
	st2 := e.LoadState()
	if st2.Desktop != "kde" || st2.Boot != "systemd-boot" || st2.UserShell != "fish" {
		t.Errorf("LoadState 回读不一致: %+v", st2)
	}
	if !contains(st2.SystemModules, "webui") || !contains(st2.Advanced, "secrets") {
		t.Errorf("LoadState 多选回读不一致: %+v", st2)
	}
}

func TestValidateRejectsUnknown(t *testing.T) {
	e := setup(t)
	st := DefaultState()
	st.Desktop = "../../etc/passwd" // 非法值
	if err := e.Validate(st); err == nil {
		t.Error("非法桌面值应被拒绝")
	}
	st2 := DefaultState()
	st2.SystemModules = []string{"evil-module"}
	if err := e.Validate(st2); err == nil {
		t.Error("未知系统模块应被拒绝")
	}
}

func TestPackagesRoundtrip(t *testing.T) {
	e := setup(t)
	list, err := e.AddDeclarativePackage("htop")
	if err != nil {
		t.Fatal(err)
	}
	if !contains(list, "htop") {
		t.Fatal("添加 htop 失败")
	}
	list, err = e.AddDeclarativePackage("ripgrep")
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 {
		t.Fatalf("应有两个包，got %v", list)
	}
	list, err = e.RemoveDeclarativePackage("htop")
	if err != nil {
		t.Fatal(err)
	}
	if contains(list, "htop") || !contains(list, "ripgrep") {
		t.Fatalf("删除 htop 失败: %v", list)
	}
	// 再读一次验证持久化格式
	list, err = e.DeclarativePackages()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0] != "ripgrep" {
		t.Fatalf("持久化读回失败: %v", list)
	}
}

func TestOverview(t *testing.T) {
	e := setup(t)
	ov, err := e.Overview()
	if err != nil {
		t.Fatal(err)
	}
	if ov.Single["desktop"].Current != "xfce" {
		t.Errorf("desktop current = %q, want xfce", ov.Single["desktop"].Current)
	}
	if ov.Single["boot"].Current != "grub-theme" {
		t.Errorf("boot current = %q, want grub-theme", ov.Single["boot"].Current)
	}
	found := false
	for _, m := range ov.Multi["system"].Options {
		if m.Name == "webui" && !m.Enabled {
			found = true
		}
	}
	if !found {
		t.Error("system 多选组应包含未启用的 webui 选项")
	}
	if len(ov.Other) == 0 {
		t.Error("应展示其他模块（network/users 等）")
	}
}
