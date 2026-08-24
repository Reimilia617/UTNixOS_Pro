package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ---------- 模块清单（与 script/lib/selection.sh 的菜单保持同一套分类） ----------

// SingleGroup 是单选分类（桌面/引导/语言/输入法/镜像/Shell）。
type SingleGroup struct {
	Key     string         `json:"key"`
	Title   string         `json:"title"`
	Options []SingleOption `json:"options"`
	Current string         `json:"current"` // 当前选中的选项名
}

// SingleOption 是单选分类里的一个选项。
type SingleOption struct {
	Name    string `json:"name"`
	Enabled bool   `json:"enabled"`
}

// MultiGroup 是多选分类（系统模块/进阶模块）。
type MultiGroup struct {
	Key     string       `json:"key"`
	Title   string       `json:"title"`
	Options []ModuleItem `json:"options"`
}

// ModuleItem 是一个可启停的模块。
type ModuleItem struct {
	Name    string `json:"name"`    // 模块名（文件名去掉 .nix）
	File    string `json:"file"`    // 相对 modules/ 的路径，如 system/clean.nix
	Enabled bool   `json:"enabled"` // 当前是否启用
}

// Overview 是 GET /api/modules 的返回结构。
type Overview struct {
	Single map[string]SingleGroup `json:"single"`
	Multi  map[string]MultiGroup  `json:"multi"`
	Other  []ModuleItem           `json:"other"` // 未纳入菜单分类的模块（只读展示）
}

// singleGroups 单选分类定义（顺序即展示顺序）。
var singleGroups = []struct {
	key     string
	title   string
	dir     string
	options []string
}{
	{"desktop", "桌面环境", "desktop", []string{"xfce", "gnome", "kde", "lxqt", "hyprland", "cosmic"}},
	{"boot", "引导加载器", "boot", []string{"grub-theme", "grub-notheme", "systemd-boot"}},
	{"locale", "语言环境", "locale", []string{"en_US", "zh_CN"}},
	{"input", "输入法", "input", []string{"ibus", "fcitx5"}},
	{"mirrors", "镜像源", "mirrors", []string{"ustc", "tuna", "nju"}},
	{"shell", "默认 Shell", "shell", []string{"zsh", "bash", "fish"}},
}

// systemModules / advancedModules 与 selection.sh 中的列表一致（webui 为本面板自身）。
var systemModules = []string{"auto-update", "clean", "nix-command", "zram", "fonts", "nopwdtodesktop", "vm-debug", "webui"}
var advancedModules = []string{"secrets", "impermanence", "backup", "security"}

// optionFiles 返回某个单选选项对应的模块文件列表（boot 特殊：grub-theme=grub+主题）。
func optionFiles(key, name string) []string {
	if key == "boot" {
		switch name {
		case "grub-theme":
			return []string{"boot/grub.nix", "boot/grub-theme.nix"}
		case "grub-notheme":
			return []string{"boot/grub.nix"}
		case "systemd-boot":
			return []string{"boot/systemd-boot.nix"}
		}
		return nil
	}
	return []string{key + "/" + name + ".nix"}
}

// Overview 生成模块总览（扫描 modules/ 目录 + 读取 configuration.nix 启停状态）。
func (e *Editor) Overview() (*Overview, error) {
	ov := &Overview{
		Single: map[string]SingleGroup{},
		Multi:  map[string]MultiGroup{},
	}

	for _, g := range singleGroups {
		sg := SingleGroup{Key: g.key, Title: g.title}
		for _, name := range g.options {
			enabled := true
			for _, f := range optionFiles(g.key, name) {
				if !e.ModuleEnabled(f) {
					enabled = false
					break
				}
			}
			sg.Options = append(sg.Options, SingleOption{Name: name, Enabled: enabled})
			// 当前选中项 = 第一个所有文件都启用的选项（选项按"最具体优先"排列）
			if sg.Current == "" && enabled {
				sg.Current = name
			}
		}
		ov.Single[g.key] = sg
	}

	ov.Multi["system"] = MultiGroup{Key: "system", Title: "系统模块", Options: e.itemsFor(systemModules)}
	ov.Multi["advanced"] = MultiGroup{Key: "advanced", Title: "进阶模块", Options: e.itemsFor(advancedModules)}

	// 其他模块（扫描 modules/ 目录，排除上面已管理的）
	managed := map[string]bool{}
	for _, g := range singleGroups {
		for _, name := range g.options {
			for _, f := range optionFiles(g.key, name) {
				managed[f] = true
			}
		}
	}
	for _, m := range systemModules {
		managed["system/"+m+".nix"] = true
	}
	for _, m := range advancedModules {
		managed["system/"+m+".nix"] = true
	}

	modsDir := e.dir + "/modules"
	var others []ModuleItem
	_ = filepath.WalkDir(modsDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(d.Name(), ".nix") {
			return nil
		}
		rel, err := filepath.Rel(modsDir, path)
		if err != nil || managed[rel] {
			return nil
		}
		others = append(others, ModuleItem{
			Name:    strings.TrimSuffix(d.Name(), ".nix"),
			File:    rel,
			Enabled: e.ModuleEnabled(rel),
		})
		return nil
	})
	sort.Slice(others, func(i, j int) bool { return others[i].File < others[j].File })
	ov.Other = others

	return ov, nil
}

func (e *Editor) itemsFor(names []string) []ModuleItem {
	var out []ModuleItem
	for _, n := range names {
		file := "system/" + n + ".nix"
		out = append(out, ModuleItem{Name: n, File: file, Enabled: e.ModuleEnabled(file)})
	}
	return out
}

// ---------- 选择状态（.utnixos-selection，与 TUI 共用） ----------

// State 是一份完整的模块选择。
type State struct {
	Desktop       string   `json:"desktop"`
	Boot          string   `json:"boot"`
	Locale        string   `json:"locale"`
	Input         string   `json:"input"`
	Mirror        string   `json:"mirror"`
	UserShell     string   `json:"userShell"`
	SystemModules []string `json:"systemModules"`
	Advanced      []string `json:"advanced"`
}

// DefaultState 与 selection.sh 的 run_menu 默认值一致。
func DefaultState() State {
	return State{
		Desktop:       "xfce",
		Boot:          "grub-theme",
		Locale:        "en_US",
		Input:         "ibus",
		Mirror:        "ustc",
		UserShell:     "zsh",
		SystemModules: []string{"auto-update", "clean", "nix-command", "zram", "fonts"},
	}
}

// LoadState 从 .utnixos-selection 读取（文件不存在时返回默认值）。
func (e *Editor) LoadState() State {
	st := DefaultState()
	data, err := os.ReadFile(e.dir + "/.utnixos-selection")
	if err != nil {
		return st
	}
	vals := map[string]string{}
	for _, ln := range strings.Split(string(data), "\n") {
		ln = strings.TrimSpace(ln)
		if ln == "" || strings.HasPrefix(ln, "#") {
			continue
		}
		if k, v, ok := strings.Cut(ln, "="); ok {
			vals[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	if v, ok := vals["DESKTOP"]; ok && v != "" {
		st.Desktop = v
	}
	if v, ok := vals["BOOT"]; ok && v != "" {
		st.Boot = v
	}
	if v, ok := vals["LOCALE"]; ok && v != "" {
		st.Locale = v
	}
	if v, ok := vals["INPUT"]; ok && v != "" {
		st.Input = v
	}
	if v, ok := vals["MIRROR"]; ok && v != "" {
		st.Mirror = v
	}
	if v, ok := vals["USERSHELL"]; ok && v != "" {
		st.UserShell = v
	}
	if v, ok := vals["SYSTEM_MODULES"]; ok {
		st.SystemModules = splitFields(v)
	}
	if v, ok := vals["ADVANCED"]; ok {
		st.Advanced = splitFields(v)
	}
	return st
}

func splitFields(s string) []string {
	var out []string
	for _, f := range strings.Fields(s) {
		out = append(out, f)
	}
	return out
}

// SaveState 把选择写入 .utnixos-selection（与 TUI 同格式，可互相读取）。
func (e *Editor) SaveState(st State) error {
	content := fmt.Sprintf(`# UTNixOS 模块选择状态（由 Web 管理面板 / install.sh 生成，可手动修改后重新运行 update）
DESKTOP=%s
BOOT=%s
LOCALE=%s
INPUT=%s
MIRROR=%s
USERSHELL=%s
SYSTEM_MODULES=%s
ADVANCED=%s
`,
		st.Desktop, st.Boot, st.Locale, st.Input, st.Mirror, st.UserShell,
		strings.Join(st.SystemModules, " "), strings.Join(st.Advanced, " "))
	return os.WriteFile(e.dir+"/.utnixos-selection", []byte(content), 0o644)
}

// ---------- 应用选择（等价 selection.sh 的 apply_selection） ----------

// Validate 校验 State 的取值是否都在白名单内。
func (e *Editor) Validate(st State) error {
	known := func(list []string, v string) bool {
		for _, x := range list {
			if x == v {
				return true
			}
		}
		return false
	}
	for _, g := range singleGroups {
		var current string
		switch g.key {
		case "desktop":
			current = st.Desktop
		case "boot":
			current = st.Boot
		case "locale":
			current = st.Locale
		case "input":
			current = st.Input
		case "mirrors":
			current = st.Mirror
		case "shell":
			current = st.UserShell
		}
		if !known(g.options, current) {
			return fmt.Errorf("%s 的值 %q 不在白名单内", g.title, current)
		}
	}
	for _, m := range st.SystemModules {
		if !known(systemModules, m) {
			return fmt.Errorf("系统模块 %q 不在白名单内", m)
		}
	}
	for _, m := range st.Advanced {
		if !known(advancedModules, m) {
			return fmt.Errorf("进阶模块 %q 不在白名单内", m)
		}
	}
	return nil
}

// Apply 把 State 写入 configuration.nix + home-manager.nix + 状态文件。
// 返回修改摘要；不会触发重建（重建由 /api/ops 完成）。
func (e *Editor) Apply(st State) ([]string, error) {
	if err := e.Validate(st); err != nil {
		return nil, err
	}
	var changed []string

	// 单选分类：先注释整个分类，再取消注释选中的
	for _, g := range singleGroups {
		var current string
		switch g.key {
		case "desktop":
			current = st.Desktop
		case "boot":
			current = st.Boot
		case "locale":
			current = st.Locale
		case "input":
			current = st.Input
		case "mirrors":
			current = st.Mirror
		case "shell":
			current = st.UserShell
		}
		if err := e.commentCategory(g.key); err != nil {
			return nil, err
		}
		for _, f := range optionFiles(g.key, current) {
			if err := e.SetModuleEnabled(f, true); err != nil {
				return nil, err
			}
		}
		changed = append(changed, fmt.Sprintf("%s -> %s", g.title, current))
	}

	// 多选：系统模块
	for _, m := range systemModules {
		on := contains(st.SystemModules, m)
		if e.ModuleEnabled("system/"+m+".nix") != on {
			if err := e.SetModuleEnabled("system/"+m+".nix", on); err != nil {
				return nil, err
			}
			changed = append(changed, fmt.Sprintf("系统模块 %s %s", m, onOff(on)))
		}
	}
	// 多选：进阶模块
	for _, m := range advancedModules {
		on := contains(st.Advanced, m)
		if e.ModuleEnabled("system/"+m+".nix") != on {
			if err := e.SetModuleEnabled("system/"+m+".nix", on); err != nil {
				return nil, err
			}
			changed = append(changed, fmt.Sprintf("进阶模块 %s %s", m, onOff(on)))
		}
	}

	// home-manager shell 同步
	if err := e.setHomeShell(st.UserShell); err != nil {
		return nil, err
	}
	changed = append(changed, "home-manager shell -> "+st.UserShell)

	if err := e.SaveState(st); err != nil {
		return nil, err
	}
	changed = append(changed, "状态文件已保存 (.utnixos-selection)")
	return changed, nil
}

func onOff(on bool) string {
	if on {
		return "启用"
	}
	return "关闭"
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}
