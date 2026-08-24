package config

import (
	"os"
	"regexp"
	"sort"
	"strings"
)

// hostPackagesFile 是 Web 面板安装的软件包清单（机器本地文件，update.sh 会保护它）。
const hostPackagesFile = "/host/packages.nix"

// declarativePackagesTemplate 是 host/packages.nix 的初始内容。
const declarativePackagesTemplate = `# UTNixOS - Web 管理面板安装的软件包（机器本地文件，自动维护）
# 警告：此文件由 Web 管理面板写入，请勿手动编辑；手动编辑请保持本格式。
# 更新配置（ut update）时会自动保留本文件。
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
  ];
}
`

var pkgEntryRe = regexp.MustCompile(`(?m)^\s*([A-Za-z0-9_][A-Za-z0-9_.+-]*)\s*$`)

// EnsurePackagesFile 确保 host/packages.nix 存在（缺失时写入空模板）。
func (e *Editor) EnsurePackagesFile() error {
	path := e.dir + hostPackagesFile
	if _, err := os.Stat(path); err == nil {
		return nil
	}
	if err := os.MkdirAll(e.dir+"/host", 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(declarativePackagesTemplate), 0o644)
}

// DeclarativePackages 读取 host/packages.nix 中的包属性名列表。
func (e *Editor) DeclarativePackages() ([]string, error) {
	if err := e.EnsurePackagesFile(); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(e.dir + hostPackagesFile)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, m := range pkgEntryRe.FindAllStringSubmatch(string(data), -1) {
		out = append(out, m[1])
	}
	return out, nil
}

// writeDeclarativePackages 重新生成 host/packages.nix。
func (e *Editor) writeDeclarativePackages(attrs []string) error {
	if err := e.EnsurePackagesFile(); err != nil {
		return err
	}
	sort.Strings(attrs)
	var b strings.Builder
	b.WriteString(`# UTNixOS - Web 管理面板安装的软件包（机器本地文件，自动维护）
# 警告：此文件由 Web 管理面板写入，请勿手动编辑；手动编辑请保持本格式。
# 更新配置（ut update）时会自动保留本文件。
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
`)
	for _, a := range attrs {
		b.WriteString("    " + a + "\n")
	}
	b.WriteString(`  ];
}
`)
	return os.WriteFile(e.dir+hostPackagesFile, []byte(b.String()), 0o644)
}

// AddDeclarativePackage 添加一个包到声明式列表（返回新列表）。
func (e *Editor) AddDeclarativePackage(attr string) ([]string, error) {
	list, err := e.DeclarativePackages()
	if err != nil {
		return nil, err
	}
	for _, a := range list {
		if a == attr {
			return list, nil // 已存在
		}
	}
	list = append(list, attr)
	if err := e.writeDeclarativePackages(list); err != nil {
		return nil, err
	}
	return list, nil
}

// RemoveDeclarativePackage 从声明式列表移除一个包（返回新列表）。
func (e *Editor) RemoveDeclarativePackage(attr string) ([]string, error) {
	list, err := e.DeclarativePackages()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, a := range list {
		if a != attr {
			out = append(out, a)
		}
	}
	if err := e.writeDeclarativePackages(out); err != nil {
		return nil, err
	}
	return out, nil
}
