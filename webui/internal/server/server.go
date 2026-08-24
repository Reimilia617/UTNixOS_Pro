// Package server 实现 HTTP 路由、会话、安全中间件与全部 API handler。
package server

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"utnixos.dev/webui/web"
)

// Options 是 Web 服务配置。
type Options struct {
	Addr         string
	ConfigDir    string
	StateDir     string
	PAMService   string
	AllowedGroup string
	SessionTTL   time.Duration
}

// Server 持有服务状态。
type Server struct {
	opts     Options
	sessions *SessionStore
	ops      *OpManager
	limiter  *loginLimiter
}

// New 创建 Server。
func New(opts Options) (*Server, error) {
	if opts.Addr == "" {
		opts.Addr = "127.0.0.1:8090"
	}
	if opts.ConfigDir == "" {
		opts.ConfigDir = "/etc/nixos"
	}
	if opts.StateDir == "" {
		opts.StateDir = "/var/lib/utnixos-webui"
	}
	if opts.PAMService == "" {
		opts.PAMService = "utnixos-webui"
	}
	if opts.SessionTTL <= 0 {
		opts.SessionTTL = 8 * time.Hour
	}
	if err := os.MkdirAll(opts.StateDir, 0o750); err != nil {
		return nil, err
	}
	return &Server{
		opts:     opts,
		sessions: NewSessionStore(opts.SessionTTL),
		ops:      NewOpManager(),
		limiter:  newLoginLimiter(),
	}, nil
}

// Routes 组装全部路由。
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("POST /api/login", s.handleLogin)
	mux.HandleFunc("POST /api/logout", s.withSession(s.handleLogout))
	mux.HandleFunc("GET /api/me", s.withSession(s.handleMe))

	mux.HandleFunc("GET /api/status", s.withSession(s.handleStatus))
	mux.HandleFunc("GET /api/modules", s.withSession(s.handleModules))
	mux.HandleFunc("POST /api/modules/apply", s.withSession(s.handleModulesApply))

	mux.HandleFunc("GET /api/packages", s.withSession(s.handlePackages))
	mux.HandleFunc("GET /api/packages/search", s.withSession(s.handlePackageSearch))
	mux.HandleFunc("POST /api/packages/validate", s.withSession(s.handlePackageValidate))
	mux.HandleFunc("POST /api/packages/declarative", s.withSession(s.handlePackageDeclarative))

	mux.HandleFunc("GET /api/generations", s.withSession(s.handleGenerations))
	mux.HandleFunc("POST /api/rollback", s.withSession(s.handleRollback))

	mux.HandleFunc("POST /api/ops", s.withSession(s.handleStartOp))
	mux.HandleFunc("GET /api/ops", s.withSession(s.handleListOps))
	mux.HandleFunc("POST /api/ops/{id}/cancel", s.withSession(s.handleCancelOp))
	mux.HandleFunc("GET /api/ops/{id}/stream", s.withSession(s.handleOpStream))

	mux.HandleFunc("GET /api/logs", s.withSession(s.handleLogs))
	mux.HandleFunc("GET /api/logs/units", s.withSession(s.handleLogUnits))
	mux.HandleFunc("GET /api/logs/stream", s.withSession(s.handleLogsStream))

	mux.HandleFunc("GET /api/audit", s.withSession(s.handleAudit))

	// 前端静态资源（go:embed，剥离 static/ 前缀后直接挂根路径）
	staticFS, err := fs.Sub(web.Static, "static")
	if err != nil {
		panic(err)
	}
	mux.Handle("/", http.FileServerFS(staticFS))

	return s.security(mux)
}

// ---------- 会话上下文 ----------

type ctxKey int

const ctxKeySession ctxKey = 0

func sessionFrom(r *http.Request) *Session {
	if v := r.Context().Value(ctxKeySession); v != nil {
		return v.(*Session)
	}
	return nil
}

// ---------- 中间件 ----------

func (s *Server) withSession(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		c, err := r.Cookie("utnixos_session")
		if err != nil {
			httpError(w, http.StatusUnauthorized, "未登录")
			return
		}
		sess := s.sessions.Get(c.Value)
		if sess == nil {
			httpError(w, http.StatusUnauthorized, "会话已过期，请重新登录")
			return
		}
		ctx := context.WithValue(r.Context(), ctxKeySession, sess)
		h(w, r.WithContext(ctx))
	}
}

func (s *Server) security(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")

		// 简单 CSRF 防护：非安全方法要求 Origin 与 Host 同源（跨站表单无法伪造）
		if r.Method != http.MethodGet && r.Method != http.MethodHead && r.Method != http.MethodOptions {
			if origin := r.Header.Get("Origin"); origin != "" && !sameOrigin(origin, r) {
				httpError(w, http.StatusForbidden, "跨站请求被拒绝")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func sameOrigin(origin string, r *http.Request) bool {
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return u.Host == r.Host
}

// ---------- 基础 handler ----------

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, map[string]any{"ok": true})
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	if sess != nil {
		s.sessions.Delete(sess.Token)
		s.audit(sess.User, "logout", "")
	}
	http.SetCookie(w, &http.Cookie{
		Name: "utnixos_session", Value: "", Path: "/",
		HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: -1,
	})
	writeJSON(w, map[string]any{"ok": true})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	sess := sessionFrom(r)
	writeJSON(w, map[string]any{"user": sess.User})
}

// ---------- 工具 ----------

func httpError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any, maxBytes int64) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return errors.New("请求 JSON 格式错误: " + err.Error())
	}
	return nil
}

// attrName 校验 nix 属性名（包名），拒绝路径穿越/注入。
func attrName(s string) bool {
	if len(s) == 0 || len(s) > 200 {
		return false
	}
	if strings.Contains(s, "..") || strings.HasPrefix(s, ".") {
		return false
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' ||
			c == '_' || c == '.' || c == '-' || c == '+') {
			return false
		}
	}
	return true
}

// unitName 校验 systemd unit 名。
func unitName(s string) bool {
	if len(s) == 0 || len(s) > 100 {
		return false
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' ||
			c == '@' || c == '.' || c == '_' || c == '-' || c == ':') {
			return false
		}
	}
	return true
}

// ---------- 审计日志 ----------

func (s *Server) audit(user, action, detail string) {
	rec := map[string]string{
		"ts":     time.Now().Format(time.RFC3339),
		"user":   user,
		"action": action,
		"detail": detail,
	}
	b, err := json.Marshal(rec)
	if err != nil {
		return
	}
	f, err := os.OpenFile(s.opts.StateDir+"/audit.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o640)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(b, '\n'))
}

// ---------- 登录限速 ----------

type loginLimiter struct {
	mu    sync.Mutex
	fails map[string][]time.Time
}

func newLoginLimiter() *loginLimiter {
	return &loginLimiter{fails: map[string][]time.Time{}}
}

// allowed 判断该 IP 是否还有登录尝试额度（窗口 1 分钟最多 5 次失败）。
func (l *loginLimiter) allowed(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	cut := now.Add(-time.Minute)
	var recent []time.Time
	for _, t := range l.fails[ip] {
		if t.After(cut) {
			recent = append(recent, t)
		}
	}
	if len(recent) >= 5 {
		l.fails[ip] = recent
		return false
	}
	l.fails[ip] = recent
	return true
}

func (l *loginLimiter) fail(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	l.fails[ip] = append(l.fails[ip], now)
	cut := now.Add(-time.Minute)
	var recent []time.Time
	for _, t := range l.fails[ip] {
		if t.After(cut) {
			recent = append(recent, t)
		}
	}
	l.fails[ip] = recent
}
