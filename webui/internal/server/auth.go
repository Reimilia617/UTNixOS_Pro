package server

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// ---------- 会话 ----------

// Session 是一次已认证会话。
type Session struct {
	Token   string
	User    string
	Expires time.Time
}

// SessionStore 是内存会话表（单实例部署，无需持久化）。
type SessionStore struct {
	mu       sync.Mutex
	sessions map[string]*Session
	ttl      time.Duration
}

// NewSessionStore 创建会话表并启动过期清理。
func NewSessionStore(ttl time.Duration) *SessionStore {
	s := &SessionStore{sessions: map[string]*Session{}, ttl: ttl}
	go s.cleanup()
	return s
}

func (s *SessionStore) Create(user string) *Session {
	tok := make([]byte, 32)
	_, _ = rand.Read(tok)
	sess := &Session{
		Token:   hex.EncodeToString(tok),
		User:    user,
		Expires: time.Now().Add(s.ttl),
	}
	s.mu.Lock()
	s.sessions[sess.Token] = sess
	s.mu.Unlock()
	return sess
}

func (s *SessionStore) Get(token string) *Session {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[token]
	if !ok {
		return nil
	}
	if time.Now().After(sess.Expires) {
		delete(s.sessions, token)
		return nil
	}
	return sess
}

func (s *SessionStore) Delete(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, token)
}

func (s *SessionStore) cleanup() {
	for {
		time.Sleep(10 * time.Minute)
		now := time.Now()
		s.mu.Lock()
		for k, v := range s.sessions {
			if now.After(v.Expires) {
				delete(s.sessions, k)
			}
		}
		s.mu.Unlock()
	}
}

// ---------- PAM 认证（通过 pamtester 调用，无 cgo） ----------

// pamAuthenticate 用系统 PAM 栈验证用户名/密码。
// pamtester -p 会从 stdin 读取密码；先做 authenticate 再查账户状态 acct_mgmt。
func pamAuthenticate(service, user, password string) error {
	if service == "" || user == "" {
		return errors.New("service/user 不能为空")
	}
	if err := pamtesterRun(service, user, password, "authenticate"); err != nil {
		return err
	}
	if err := pamtesterRun(service, user, password, "acct_mgmt"); err != nil {
		return errors.New("账户不可用: " + err.Error())
	}
	return nil
}

func pamtesterRun(service, user, password, action string) error {
	cmd := exec.Command("pamtester", "-p", service, user, action)
	cmd.Stdin = strings.NewReader(password + "\n")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return errors.New(msg)
	}
	return nil
}

// userInGroup 检查用户是否在指定组（解析 /etc/group，避免 cgo os/user）。
func userInGroup(username, group string) (bool, error) {
	if group == "" {
		return true, nil
	}
	data, err := os.ReadFile("/etc/group")
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		parts := strings.Split(line, ":")
		if len(parts) < 4 || parts[0] != group {
			continue
		}
		for _, u := range strings.Split(parts[3], ",") {
			if u == username {
				return true, nil
			}
		}
	}
	return false, nil
}

// ---------- 登录 handler ----------

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &req, 1<<16); err != nil {
		httpError(w, http.StatusBadRequest, "请求格式错误")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || req.Password == "" {
		httpError(w, http.StatusBadRequest, "用户名和密码不能为空")
		return
	}
	if req.Username == "root" {
		httpError(w, http.StatusForbidden, "禁止使用 root 登录管理面板，请用普通用户")
		return
	}

	ip := clientIP(r)
	if !s.limiter.allowed(ip) {
		httpError(w, http.StatusTooManyRequests, "尝试过于频繁，请 1 分钟后再试")
		return
	}

	if err := pamAuthenticate(s.opts.PAMService, req.Username, req.Password); err != nil {
		s.limiter.fail(ip)
		httpError(w, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	if s.opts.AllowedGroup != "" {
		ok, err := userInGroup(req.Username, s.opts.AllowedGroup)
		if err != nil || !ok {
			s.limiter.fail(ip)
			httpError(w, http.StatusForbidden, "用户不在允许的管理员组（"+s.opts.AllowedGroup+"）中")
			return
		}
	}

	sess := s.sessions.Create(req.Username)
	http.SetCookie(w, &http.Cookie{
		Name:     "utnixos_pro_session",
		Value:    sess.Token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(s.opts.SessionTTL.Seconds()),
	})
	s.audit(sess.User, "login", "登录成功")
	writeJSON(w, map[string]any{"user": sess.User})
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
