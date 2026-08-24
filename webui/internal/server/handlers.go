package server

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"

	"utnixos.dev/webui/internal/config"
	"utnixos.dev/webui/internal/nix"
)

// cfgEditor 便捷获取配置编辑器。
func (s *Server) cfgEditor() (*config.Editor, error) {
	return config.NewEditor(s.opts.ConfigDir)
}

// ---------- 状态 ----------

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	st := nix.GetStatus(s.opts.ConfigDir)
	writeJSON(w, st)
}

// ---------- 模块 ----------

func (s *Server) handleModules(w http.ResponseWriter, r *http.Request) {
	e, err := s.cfgEditor()
	if err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	ov, err := e.Overview()
	if err != nil {
		httpError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, ov)
}

func (s *Server) handleModulesApply(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	var req struct {
		Selection config.State `json:"selection"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	e, err := s.cfgEditor()
	if err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	changed, err := e.Apply(req.Selection)
	if err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	s.audit(sess.User, "modules.apply", strings.Join(changed, "; "))
	writeJSON(w, map[string]any{"changed": changed})
}

// ---------- 软件包 ----------

func (s *Server) handlePackages(w http.ResponseWriter, r *http.Request) {
	e, err := s.cfgEditor()
	if err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	decl, err := e.DeclarativePackages()
	if err != nil {
		httpError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if decl == nil {
		decl = []string{}
	}
	temp, err := nix.ListProfile()
	if err != nil {
		// profile 可能不存在（从未临时装过包），不报错
		temp = []nix.ProfileEntry{}
	}
	var tempOnly []nix.ProfileEntry
	for _, p := range temp {
		if strings.HasPrefix(p.Name, "nixpkgs#") {
			tempOnly = append(tempOnly, p)
		}
	}
	if tempOnly == nil {
		tempOnly = []nix.ProfileEntry{}
	}
	writeJSON(w, map[string]any{
		"declarative": decl,
		"temp":        tempOnly,
	})
}

// handlePackageSearch 搜索 nixpkgs（较慢，超时 120 秒）。
func (s *Server) handlePackageSearch(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeJSON(w, map[string]any{"results": []nix.SearchResult{}})
		return
	}
	if len(q) > 100 {
		httpError(w, http.StatusBadRequest, "搜索词过长")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 120*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "nix", "search", "nixpkgs", "--json", q).CombinedOutput()
	if err != nil {
		httpError(w, http.StatusGatewayTimeout, "搜索失败（nix search 超时或出错），请稍后重试")
		return
	}
	results := nix.ParseSearchJSON(out)
	writeJSON(w, map[string]any{"results": results})
}

// handlePackageValidate 校验包属性是否存在（nix eval）。
func (s *Server) handlePackageValidate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Attr string `json:"attr"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	req.Attr = strings.TrimSpace(req.Attr)
	if !attrName(req.Attr) {
		httpError(w, http.StatusBadRequest, "包属性名不合法")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	if err := exec.CommandContext(ctx, "nix", "eval", "--raw", "nixpkgs#"+req.Attr).Run(); err != nil {
		httpError(w, http.StatusNotFound, "nixpkgs 中找不到属性 "+req.Attr)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "attr": req.Attr})
}

// handlePackageDeclarative 声明式安装/卸载（写入 host/packages.nix，不自动重建）。
func (s *Server) handlePackageDeclarative(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	var req struct {
		Attr   string `json:"attr"`
		Remove bool   `json:"remove"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	req.Attr = strings.TrimSpace(req.Attr)
	if !attrName(req.Attr) {
		httpError(w, http.StatusBadRequest, "包属性名不合法")
		return
	}
	e, err := s.cfgEditor()
	if err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	var list []string
	if req.Remove {
		list, err = e.RemoveDeclarativePackage(req.Attr)
	} else {
		// 先校验属性存在
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		if err := exec.CommandContext(ctx, "nix", "eval", "--raw", "nixpkgs#"+req.Attr).Run(); err != nil {
			httpError(w, http.StatusNotFound, "nixpkgs 中找不到属性 "+req.Attr)
			return
		}
		list, err = e.AddDeclarativePackage(req.Attr)
	}
	if err != nil {
		httpError(w, http.StatusInternalServerError, err.Error())
		return
	}
	action := "declarative.add"
	if req.Remove {
		action = "declarative.remove"
	}
	s.audit(sess.User, action, req.Attr)
	writeJSON(w, map[string]any{"list": list, "note": "已写入配置，点击「重建系统」生效"})
}

// ---------- generations / 回滚 ----------

func (s *Server) handleGenerations(w http.ResponseWriter, r *http.Request) {
	gens, err := nix.ListGenerations()
	if err != nil {
		httpError(w, http.StatusInternalServerError, "读取 generations 失败: "+err.Error())
		return
	}
	writeJSON(w, map[string]any{"generations": gens, "current": nix.CurrentGeneration()})
}

func (s *Server) handleRollback(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	var req struct {
		Generation int `json:"generation"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}
	gens, err := nix.ListGenerations()
	if err != nil {
		httpError(w, http.StatusInternalServerError, "读取 generations 失败: "+err.Error())
		return
	}
	valid := false
	for _, g := range gens {
		if g.N == req.Generation {
			valid = true
			break
		}
	}
	if !valid {
		httpError(w, http.StatusBadRequest, "generation 编号无效")
		return
	}
	op, err := s.ops.StartCustom("rollback", func(emit func(string)) error {
		emit(fmt.Sprintf("== 切换到 generation %d ==", req.Generation))
		if err := streamCmd(nix.SwitchGenerationCmd(req.Generation), emit); err != nil {
			return fmt.Errorf("切换 generation 失败: %w", err)
		}
		emit("== 激活该 generation ==")
		if err := streamCmd(nix.SwitchToConfigCmd(), emit); err != nil {
			return fmt.Errorf("激活 generation 失败: %w", err)
		}
		return nil
	})
	if err != nil {
		httpError(w, http.StatusConflict, err.Error())
		return
	}
	s.audit(sess.User, "rollback", fmt.Sprintf("generation %d", req.Generation))
	writeJSON(w, map[string]any{"id": op.ID, "type": op.Type})
}

// ---------- 后台任务（重建/更新/GC/临时装包） ----------

func (s *Server) handleStartOp(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	var req struct {
		Type string `json:"type"` // rebuild | update | gc | temp-install | temp-remove
		Mode string `json:"mode"` // update 用: config | flake
		Attr string `json:"attr"` // temp-install 用
		Gen  int    `json:"generation"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, err.Error())
		return
	}

	var op *Op
	var err error

	switch req.Type {
	case "rebuild":
		e, eerr := s.cfgEditor()
		if eerr != nil {
			httpError(w, http.StatusBadRequest, eerr.Error())
			return
		}
		if err := e.EnsurePackagesFile(); err != nil {
			httpError(w, http.StatusInternalServerError, err.Error())
			return
		}
		op, err = s.ops.Start("rebuild", nix.RebuildCmd(s.opts.ConfigDir))

	case "update":
		switch req.Mode {
		case "config":
			op, err = s.ops.StartCustom("update", s.updateConfig)
		case "flake":
			op, err = s.ops.StartCustom("update", s.updateFlake)
		default:
			httpError(w, http.StatusBadRequest, "update 的 mode 必须是 config 或 flake")
			return
		}

	case "gc":
		op, err = s.ops.Start("gc", nix.GcCmd())

	case "temp-install":
		req.Attr = strings.TrimSpace(req.Attr)
		if !attrName(req.Attr) {
			httpError(w, http.StatusBadRequest, "包属性名不合法")
			return
		}
		op, err = s.ops.Start("temp-install", nix.ProfileInstallCmd(req.Attr))

	case "temp-remove":
		req.Attr = strings.TrimSpace(req.Attr)
		if !attrName(req.Attr) {
			httpError(w, http.StatusBadRequest, "包属性名不合法")
			return
		}
		attr := req.Attr
		op, err = s.ops.StartCustom("temp-remove", func(emit func(string)) error {
			entries, lerr := nix.ListProfile()
			if lerr != nil {
				return lerr
			}
			idx := ""
			for _, p := range entries {
				if p.Name == "nixpkgs#"+attr {
					idx = p.Index
					break
				}
			}
			if idx == "" {
				return fmt.Errorf("profile 中找不到 %s", attr)
			}
			emit("nix profile remove " + idx + " (" + attr + ")")
			return streamCmd(nix.ProfileRemoveCmd(idx), emit)
		})

	default:
		httpError(w, http.StatusBadRequest, "未知任务类型: "+req.Type)
		return
	}

	if err != nil {
		httpError(w, http.StatusConflict, err.Error())
		return
	}
	s.audit(sess.User, "op."+req.Type, fmt.Sprintf("%+v", req))
	writeJSON(w, map[string]any{"id": op.ID, "type": op.Type})
}

func (s *Server) handleListOps(w http.ResponseWriter, r *http.Request) {
	op := s.ops.Current()
	if op == nil {
		writeJSON(w, map[string]any{"op": nil})
		return
	}
	writeJSON(w, map[string]any{"op": op})
}

func (s *Server) handleCancelOp(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	op := s.ops.Current()
	if op == nil || op.ID != r.PathValue("id") {
		httpError(w, http.StatusNotFound, "任务不存在")
		return
	}
	op.Cancel()
	s.audit(sess.User, "op.cancel", op.ID)
	writeJSON(w, map[string]any{"ok": true})
}

// ---------- 更新流程 ----------

// updateConfig 同步 GitHub 代码 + 恢复机器本地文件 + 重新应用模块选择 + 重建。
func (s *Server) updateConfig(emit func(string)) error {
	dir := s.opts.ConfigDir
	emit("== 更新配置（同步 GitHub 代码 + 重建）==")

	if _, err := os.Stat(dir + "/.git"); err != nil {
		emit("! 配置目录没有 .git，跳过代码同步（直接重建）")
		return s.runRebuild(emit)
	}

	// 备份机器本地文件
	backup := make(map[string]string)
	for _, f := range []string{"hardware-configuration.nix", "host/packages.nix"} {
		data, err := os.ReadFile(dir + "/" + f)
		if err == nil {
			backup[f] = string(data)
		}
	}

	emit("git fetch origin ...")
	if out, err := gitCmd(dir, "fetch", "origin").CombinedOutput(); err != nil {
		emit("! git fetch 失败（网络问题？），使用本地已有代码: " + strings.TrimSpace(string(out)))
		return s.runRebuild(emit)
	}

	emit("git reset --hard origin/main ...")
	if out, err := gitCmd(dir, "reset", "--hard", "origin/main").CombinedOutput(); err != nil {
		emit(strings.TrimSpace(string(out)))
		return fmt.Errorf("git reset 失败: %v", err)
	}

	// 恢复机器本地文件（防止被 reset 覆盖）
	for f, data := range backup {
		if f == "host/packages.nix" {
			if err := os.MkdirAll(dir+"/host", 0o755); err != nil {
				return err
			}
		}
		if err := os.WriteFile(dir+"/"+f, []byte(data), 0o644); err != nil {
			return err
		}
	}
	// 重新标记 skip-worktree（与 update.sh 一致，防止后续误覆盖）
	_ = gitCmd(dir, "update-index", "--skip-worktree",
		"hardware-configuration.nix", "host/packages.nix").Run()

	// 重新应用模块选择（.utnixos-selection 是 untracked，reset 不会动它）
	e, err := config.NewEditor(dir)
	if err != nil {
		return err
	}
	st := e.LoadState()
	emit("重新应用模块选择（.utnixos-selection）...")
	if _, err := e.Apply(st); err != nil {
		return fmt.Errorf("应用模块选择失败: %v", err)
	}

	return s.runRebuild(emit)
}

// gitCmd 在指定目录执行 git 命令（防止在错误的工作目录运行）。
func gitCmd(dir string, args ...string) *exec.Cmd {
	c := exec.Command("git", args...)
	c.Dir = dir
	return c
}

// updateFlake 更新 flake.lock + 重建。
func (s *Server) updateFlake(emit func(string)) error {
	dir := s.opts.ConfigDir
	emit("== 更新 Flake 输入（nix flake update）+ 重建 ==")
	if err := streamCmd(nix.FlakeUpdateCmd(dir), emit); err != nil {
		return fmt.Errorf("nix flake update 失败: %v", err)
	}
	return s.runRebuild(emit)
}

func (s *Server) runRebuild(emit func(string)) error {
	emit("== 开始重建系统（nixos-rebuild switch）==")
	if err := streamCmd(nix.RebuildCmd(s.opts.ConfigDir), emit); err != nil {
		return fmt.Errorf("nixos-rebuild 失败: %v", err)
	}
	emit("== 重建完成 ==")
	return nil
}

// ---------- 日志 ----------

func journalArgs(unit, lines string, follow bool) []string {
	args := []string{"-b", "-n", lines, "-o", "short"}
	if unit != "" {
		args = append(args, "-u", unit)
	}
	if follow {
		args = append(args, "-f")
	}
	return args
}

func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request) {
	unit := r.URL.Query().Get("unit")
	if unit != "" && !unitName(unit) {
		httpError(w, http.StatusBadRequest, "unit 参数不合法")
		return
	}
	lines := r.URL.Query().Get("lines")
	if lines == "" {
		lines = "200"
	}
	if _, err := strconv.Atoi(lines); err != nil {
		httpError(w, http.StatusBadRequest, "lines 参数不合法")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "journalctl", journalArgs(unit, lines, false)...).CombinedOutput()
	if err != nil {
		httpError(w, http.StatusInternalServerError, "journalctl 失败")
		return
	}
	writeJSON(w, map[string]any{"output": string(out)})
}

func (s *Server) handleLogUnits(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "systemctl", "list-units", "--type=service",
		"--no-pager", "--no-legend").CombinedOutput()
	if err != nil {
		httpError(w, http.StatusInternalServerError, "systemctl 失败")
		return
	}
	var units []string
	for _, ln := range strings.Split(string(out), "\n") {
		f := strings.Fields(ln)
		if len(f) > 0 && strings.HasSuffix(f[0], ".service") {
			units = append(units, f[0])
		}
	}
	sort.Strings(units)
	writeJSON(w, map[string]any{"units": units})
}

// handleLogsStream 实时日志（SSE，journalctl -f）。
func (s *Server) handleLogsStream(w http.ResponseWriter, r *http.Request) {
	unit := r.URL.Query().Get("unit")
	if unit != "" && !unitName(unit) {
		httpError(w, http.StatusBadRequest, "unit 参数不合法")
		return
	}
	lines := r.URL.Query().Get("lines")
	if lines == "" {
		lines = "100"
	}
	if _, err := strconv.Atoi(lines); err != nil {
		httpError(w, http.StatusBadRequest, "lines 参数不合法")
		return
	}

	fl, ok := w.(http.Flusher)
	if !ok {
		httpError(w, http.StatusInternalServerError, "连接不支持流式输出")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	cmd := exec.Command("journalctl", journalArgs(unit, lines, true)...)
	pr, pw := pipeFor(cmd)
	if err := cmd.Start(); err != nil {
		httpError(w, http.StatusInternalServerError, "journalctl 启动失败")
		return
	}
	defer func() {
		_ = cmd.Process.Kill()
		_ = pw.Close()
		_ = pr.Close()
	}()

	go func() {
		<-r.Context().Done()
		_ = cmd.Process.Kill()
	}()

	// 读取 goroutine + channel，避免 select 空转
	lineCh := make(chan string, 128)
	go func() {
		sc := bufioScanner(pr)
		for sc.Scan() {
			lineCh <- sc.Text()
		}
		close(lineCh)
	}()

	heartbeat := time.NewTicker(15 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case line, ok := <-lineCh:
			if ok {
				sseWrite(w, fl, "line", line)
				continue
			}
			return // journalctl 退出（EOF）
		case <-heartbeat.C:
			sseWrite(w, fl, "ping", "")
		case <-r.Context().Done():
			return
		}
	}
}

// ---------- 审计 ----------

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	limit := 200
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 1000 {
			limit = n
		}
	}
	data, err := os.ReadFile(s.opts.StateDir + "/audit.log")
	if err != nil {
		writeJSON(w, map[string]any{"entries": []string{}})
		return
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > limit {
		lines = lines[len(lines)-limit:]
	}
	writeJSON(w, map[string]any{"entries": lines})
}

// ---------- 流式读取辅助 ----------

func pipeFor(cmd *exec.Cmd) (pr *io.PipeReader, pw *io.PipeWriter) {
	pr, pw = io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw
	return pr, pw
}

func bufioScanner(pr io.Reader) *bufio.Scanner {
	sc := bufio.NewScanner(pr)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	return sc
}
