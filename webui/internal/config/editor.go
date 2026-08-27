// Package config 负责读写 /etc/nixos 下的配置文件：
//   - configuration.nix 的模块 imports（注释/取消注释，与 script/lib/selection.sh 的 sed 语义一致）
//   - home-manager.nix 的 shell 导入同步
//   - .utnixos-pro-selection 状态文件（与 TUI ut 菜单共用同一份状态）
//   - host/packages.nix（Web 面板安装的软件包，机器本地文件）
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

// Editor 封装对一个配置目录的读取与修改。
type Editor struct {
	dir string
}

// NewEditor 创建编辑器，目录必须是已安装的 NixOS 配置目录（含 configuration.nix）。
func NewEditor(dir string) (*Editor, error) {
	if dir == "" {
		return nil, errors.New("配置目录为空")
	}
	if _, err := os.Stat(dir + "/configuration.nix"); err != nil {
		return nil, errors.New("找不到 " + dir + "/configuration.nix")
	}
	return &Editor{dir: dir}, nil
}

// Dir 返回配置目录。
func (e *Editor) Dir() string { return e.dir }

// importLine 解析 configuration.nix 里的一行模块导入。
type importLine struct {
	raw       string // 原始行
	module    string // 形如 "system/auto-update.nix"（去掉 ./modules/ 前缀）
	commented bool   // 是否被注释（# 开头）
	matched   bool   // 是否匹配模块导入格式
}

// parseImportLine 解析一行。只识别 ./modules/ 开头的导入（与 TUI sed 行为一致）。
func parseImportLine(line string) importLine {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return importLine{raw: line}
	}
	commented := strings.HasPrefix(trimmed, "#")
	body := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
	if !strings.HasPrefix(body, "./modules/") {
		return importLine{raw: line}
	}
	idx := strings.IndexAny(body, " \t#")
	if idx < 0 {
		idx = len(body)
	}
	path := strings.TrimPrefix(body[:idx], "./modules/")
	if path == "" || path == body[:idx] {
		return importLine{raw: line}
	}
	return importLine{raw: line, module: path, commented: commented, matched: true}
}

// setCommented 在保留原始缩进与行尾注释的前提下，插入/移除行首的 #。
func setCommented(raw string, commented bool) string {
	lead := len(raw) - len(strings.TrimLeft(raw, " \t"))
	rest := raw[lead:]
	if commented {
		if strings.HasPrefix(rest, "#") {
			return raw
		}
		return raw[:lead] + "#" + rest
	}
	if strings.HasPrefix(rest, "#") {
		return raw[:lead] + rest[1:]
	}
	return raw
}

// setModuleEnabled 修改 configuration.nix 中指定模块（如 "desktop/xfce.nix"）的启停状态。
// 返回该模块是否在文件中找到。文件里没有对应行时不报错（与 TUI 行为一致）。
func (e *Editor) setModuleEnabled(module string, enabled bool) (bool, error) {
	path := e.dir + "/configuration.nix"
	data, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	lines := strings.Split(string(data), "\n")
	found := false
	for i, ln := range lines {
		il := parseImportLine(ln)
		if il.matched && il.module == module {
			lines[i] = setCommented(ln, !enabled)
			found = true
		}
	}
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
		return false, err
	}
	return found, nil
}

// SetModuleEnabled 是 setModuleEnabled 的公开封装。
func (e *Editor) SetModuleEnabled(module string, enabled bool) error {
	_, err := e.setModuleEnabled(module, enabled)
	return err
}

// ModuleEnabled 查询模块当前是否启用。
func (e *Editor) ModuleEnabled(module string) bool {
	data, err := os.ReadFile(e.dir + "/configuration.nix")
	if err != nil {
		return false
	}
	for _, ln := range strings.Split(string(data), "\n") {
		il := parseImportLine(ln)
		if il.matched && il.module == module {
			return !il.commented
		}
	}
	return false
}

// commentCategory 注释某个分类下的所有模块（如所有 modules/desktop/*）。
func (e *Editor) commentCategory(category string) error {
	path := e.dir + "/configuration.nix"
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	prefix := category + "/"
	for i, ln := range lines {
		il := parseImportLine(ln)
		if il.matched && strings.HasPrefix(il.module, prefix) {
			lines[i] = setCommented(ln, true)
		}
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644)
}

// setHomeShell 同步 home/home-manager.nix 的 shell 导入（与 selection.sh 一致）。
func (e *Editor) setHomeShell(shell string) error {
	path := e.dir + "/home/home-manager.nix"
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	for i, ln := range lines {
		trimmed := strings.TrimSpace(ln)
		commented := strings.HasPrefix(trimmed, "#")
		body := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
		name, ok := homeShellName(body)
		if !ok {
			continue
		}
		enabled := name == shell
		if commented == !enabled {
			continue
		}
		lines[i] = setCommented(ln, !enabled)
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644)
}

// homeShellName 从 "./shell/xxx.nix     # 注释" 中提取 xxx。
func homeShellName(body string) (string, bool) {
	if !strings.HasPrefix(body, "./shell/") {
		return "", false
	}
	idx := strings.IndexAny(body, " \t#")
	if idx < 0 {
		idx = len(body)
	}
	name := strings.TrimPrefix(body[:idx], "./shell/")
	if !strings.HasSuffix(name, ".nix") {
		return "", false
	}
	return strings.TrimSuffix(name, ".nix"), true
}

// writeGrubDevice 维护机器本地文件 host/grub-device.nix：
// configuration.nix 始终 import 该文件；选中 GRUB(BIOS) 时写入目标磁盘，
// 否则写成空模块（不产生任何配置）。与 selection.sh 的 write_grub_device 同语义。
func (e *Editor) writeGrubDevice(st State) error {
	f := e.dir + "/host/grub-device.nix"
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return err
	}
	if st.Boot == "grub-bios" {
		dev := strings.TrimSpace(st.GrubDevice)
		if dev == "" {
			dev = "/dev/sda"
		}
		content := fmt.Sprintf(`# UTNixOS_Pro - GRUB(BIOS) 引导设备（机器本地文件，自动维护）
# 警告：此文件由安装脚本 / Web 管理面板自动写入，请勿手动编辑；ut update 时会自动保留。
{ ... }: {
  boot.loader.grub.device = %q;
}
`, dev)
		return os.WriteFile(f, []byte(content), 0o644)
	}
	content := `# UTNixOS_Pro - GRUB(BIOS) 引导设备（机器本地文件，自动维护）
# 当前为空模块：表示未使用 GRUB(BIOS)，不产生任何配置。
{ ... }: { }
`
	return os.WriteFile(f, []byte(content), 0o644)
}
