package server

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// ---------- 任务（Op） ----------

// OpState 是任务状态。
type OpState string

const (
	OpRunning   OpState = "running"
	OpDone      OpState = "done"
	OpError     OpState = "error"
	OpCancelled OpState = "cancelled"
)

// OpEvent 是通过 SSE 推送的事件。
type OpEvent struct {
	Kind string `json:"kind"` // line | status | summary
	Data string `json:"data"`
}

// Op 是一次后台任务（重建/更新/回滚/GC/临时装包）。
type Op struct {
	ID         string    `json:"id"`
	Type       string    `json:"type"`
	State      OpState   `json:"state"`
	Summary    string    `json:"summary"`
	StartedAt  time.Time `json:"startedAt"`
	FinishedAt time.Time `json:"finishedAt"`

	mu     sync.Mutex
	lines  []string // 最近 500 行输出（新订阅者回放）
	subs   map[chan OpEvent]struct{}
	cancel context.CancelFunc
	cmd    *exec.Cmd
	runFn  func(emit func(string)) error // 自定义多步任务（如 更新=git同步+应用选择+重建）
}

func (op *Op) emitLine(line string) {
	op.mu.Lock()
	op.lines = append(op.lines, line)
	if len(op.lines) > 500 {
		op.lines = op.lines[len(op.lines)-500:]
	}
	for ch := range op.subs {
		select {
		case ch <- OpEvent{Kind: "line", Data: line}:
		default:
		}
	}
	op.mu.Unlock()
}

func (op *Op) finish(state OpState, summary string) {
	op.mu.Lock()
	op.State = state
	op.Summary = summary
	op.FinishedAt = time.Now()
	subs := make([]chan OpEvent, 0, len(op.subs))
	for ch := range op.subs {
		subs = append(subs, ch)
	}
	op.mu.Unlock()
	for _, ch := range subs {
		select {
		case ch <- OpEvent{Kind: "status", Data: string(state)}:
		default:
		}
		select {
		case ch <- OpEvent{Kind: "summary", Data: summary}:
		default:
		}
	}
}

func (op *Op) subscribe() (chan OpEvent, []string) {
	op.mu.Lock()
	defer op.mu.Unlock()
	ch := make(chan OpEvent, 256)
	op.subs[ch] = struct{}{}
	lines := make([]string, len(op.lines))
	copy(lines, op.lines)
	return ch, lines
}

func (op *Op) unsubscribe(ch chan OpEvent) {
	op.mu.Lock()
	defer op.mu.Unlock()
	delete(op.subs, ch)
}

// Cancel 请求取消任务（SIGTERM，5 秒后 SIGKILL）。
func (op *Op) Cancel() {
	if op.cancel != nil {
		op.cancel()
	}
}

// ---------- 任务管理器（单飞：同时只允许一个任务） ----------

// OpManager 管理当前任务。
type OpManager struct {
	mu  sync.Mutex
	cur *Op
}

// NewOpManager 创建任务管理器。
func NewOpManager() *OpManager {
	return &OpManager{}
}

// Current 返回当前任务（可能为 nil）。
func (m *OpManager) Current() *Op {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.cur
}

// Start 启动一个外部命令任务；若已有任务在运行则报错。
func (m *OpManager) Start(opType string, cmd *exec.Cmd) (*Op, error) {
	return m.start(opType, cmd, nil)
}

// StartCustom 启动一个 Go 函数任务（用于多步流程）。
func (m *OpManager) StartCustom(opType string, fn func(emit func(string)) error) (*Op, error) {
	return m.start(opType, nil, fn)
}

func (m *OpManager) start(opType string, cmd *exec.Cmd, fn func(emit func(string)) error) (*Op, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cur != nil && m.cur.State == OpRunning {
		return nil, errors.New("已有任务在运行，请等待完成或取消")
	}
	ctx, cancel := context.WithCancel(context.Background())
	op := &Op{
		ID:        randID(),
		Type:      opType,
		State:     OpRunning,
		StartedAt: time.Now(),
		subs:      map[chan OpEvent]struct{}{},
		cancel:    cancel,
		cmd:       cmd,
		runFn:     fn,
	}
	m.cur = op
	go op.run(ctx)
	return op, nil
}

func randID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ---------- 任务执行 ----------

func (op *Op) run(ctx context.Context) {
	if op.cmd != nil {
		op.runCommand(ctx)
		return
	}
	if op.runFn != nil {
		emit := func(line string) { op.emitLine(line) }
		if err := op.runFn(emit); err != nil {
			op.finish(OpError, err.Error())
		} else {
			op.finish(OpDone, "完成")
		}
		return
	}
	op.finish(OpError, "任务缺少执行内容")
}

func (op *Op) runCommand(ctx context.Context) {
	cmd := op.cmd
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	pr, pw := io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		op.finish(OpError, "启动失败: "+err.Error())
		return
	}

	lineCh := make(chan string, 128)
	go func() {
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			lineCh <- sc.Text()
		}
		close(lineCh)
	}()

	waitCh := make(chan error, 1)
	go func() { waitCh <- cmd.Wait() }()

	pgid := cmd.Process.Pid
	for {
		select {
		case line, ok := <-lineCh:
			if ok {
				op.emitLine(line)
				continue
			}
			lineCh = nil // EOF
		case err := <-waitCh:
			_ = pw.Close()
			if err != nil {
				op.finish(OpError, "执行失败: "+err.Error())
			} else {
				op.finish(OpDone, "完成")
			}
			return
		case <-ctx.Done():
			_ = syscall.Kill(-pgid, syscall.SIGTERM)
			select {
			case <-waitCh:
			case <-time.After(5 * time.Second):
				_ = syscall.Kill(-pgid, syscall.SIGKILL)
				<-waitCh
			}
			op.finish(OpCancelled, "已取消")
			return
		}
	}
}

// ---------- 流式辅助 ----------

// streamCmd 在一个自定义任务里执行命令并把输出逐行交给 emit。
func streamCmd(cmd *exec.Cmd, emit func(string)) error {
	pr, pw := io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			emit(sc.Text())
		}
		close(done)
	}()
	err := cmd.Wait()
	_ = pw.Close()
	<-done
	return err
}

// ---------- SSE handler ----------

func sseWrite(w http.ResponseWriter, fl http.Flusher, kind, data string) {
	fmt.Fprintf(w, "event: %s\ndata: %s\n\n", kind, strings.ReplaceAll(data, "\n", " "))
	fl.Flush()
}

func (s *Server) handleOpStream(w http.ResponseWriter, r *http.Request) {
	op := s.ops.Current()
	if op == nil || op.ID != r.PathValue("id") {
		httpError(w, http.StatusNotFound, "任务不存在")
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

	ch, lines := op.subscribe()
	defer op.unsubscribe(ch)

	// 回放历史输出
	for _, l := range lines {
		sseWrite(w, fl, "line", l)
	}

	op.mu.Lock()
	state := op.State
	op.mu.Unlock()
	if state != OpRunning {
		sseWrite(w, fl, "status", string(state))
		op.mu.Lock()
		sseWrite(w, fl, "summary", op.Summary)
		op.mu.Unlock()
		return
	}

	heartbeat := time.NewTicker(15 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case ev := <-ch:
			sseWrite(w, fl, ev.Kind, ev.Data)
			if ev.Kind == "status" {
				op.mu.Lock()
				sseWrite(w, fl, "summary", op.Summary)
				op.mu.Unlock()
				return
			}
		case <-heartbeat.C:
			sseWrite(w, fl, "ping", "")
		case <-r.Context().Done():
			return
		}
	}
}
