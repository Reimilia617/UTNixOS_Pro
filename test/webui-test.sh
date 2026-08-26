#!/usr/bin/env bash
# ============================================================================
# UTNixOS_Pro Web 管理面板容器测试（在容器内运行）
#
# 在 Debian 容器中：
#   - 安装 pamtester，创建系统用户 reimilia（wheel 组）用于 PAM 登录
#   - 配置 /etc/pam.d/utnixos-pro-webui（与 modules/system/webui.nix 一致）
#   - 把仓库复制为 /etc/nixos 作为配置目录
#   - nix/nix-env/nixos-rebuild/journalctl/systemctl 用 stub 代替
#   - 启动 webui 二进制，用 curl 测试全部 API
# ============================================================================
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
api() { curl -s -m 10 -b /tmp/cj -c /tmp/cj "$@"; }
expect_code() { # expect_code <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1（HTTP $3）"; else bad "$1（期望 $2 实际 $3）"; fi
}

# ---------- 用户与 PAM ----------
groupadd wheel 2>/dev/null || true
useradd -m reimilia
echo 'reimilia:TestPass123' | chpasswd
usermod -aG wheel reimilia
cat > /etc/pam.d/utnixos-pro-webui <<'PAM'
auth required pam_unix.so
account required pam_unix.so
PAM

# ---------- 配置目录 ----------
rm -rf /etc/nixos && mkdir -p /etc/nixos
rsync -a --exclude '.git' /repo/ /etc/nixos/
printf 'htop\n' >> /etc/nixos/host/packages.nix

# ---------- nix 相关 stub ----------
cat > /usr/local/bin/nix-env <<'STUB'
#!/bin/bash
if [[ "$*" == *--list-generations* ]]; then
  cat <<'GEN'
  21  2026-08-01 10:00:00   (current)
  22  2026-08-02 10:00:00
  23  2026-08-03 10:00:00
GEN
fi
STUB
cat > /usr/local/bin/nix <<'STUB'
#!/bin/bash
case "$1" in
  search) echo '{"legacyPackages.x86_64-linux.htop":{"pname":"htop","version":"3.3.0","description":"htop"}}' ;;
  eval) exit 0 ;;
  profile) exit 0 ;;
esac
STUB
cat > /usr/local/bin/nixos-rebuild <<'STUB'
#!/bin/bash
echo "building the system configuration..."
echo "these 5 derivations will be built:"
echo "activating the configuration..."
STUB
cat > /usr/local/bin/journalctl <<'STUB'
#!/bin/bash
echo "Aug 05 10:00:00 host journalctl stub line"
STUB
cat > /usr/local/bin/systemctl <<'STUB'
#!/bin/bash
if [[ "$*" == *list-units* ]]; then
  printf 'foo.service loaded active running Foo\nbar.service loaded active running Bar\n'
fi
STUB
chmod +x /usr/local/bin/nix-env /usr/local/bin/nix /usr/local/bin/nixos-rebuild \
  /usr/local/bin/journalctl /usr/local/bin/systemctl

# ---------- 启动 webui ----------
cp /webui-bin/webui /usr/local/bin/webui
/usr/local/bin/webui --addr 127.0.0.1:8090 --config-dir /etc/nixos \
  --state-dir /var/lib/utnixos-pro-webui --pam-service utnixos-pro-webui \
  --allowed-group wheel >/tmp/webui.log 2>&1 &
WEBUI_PID=$!
for _ in $(seq 1 30); do
  curl -s -m 2 http://127.0.0.1:8090/api/health >/dev/null 2>&1 && break
  sleep 0.5
done
echo "--- webui 启动日志 ---"; head -3 /tmp/webui.log

echo ""
echo "========== WebUI 测试 =========="

# 1. 健康检查 / 页面
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/api/health)
expect_code "GET /api/health（无认证）" 200 "$CODE"
BODY=$(api http://127.0.0.1:8090/api/health)
echo "$BODY" | grep -q '"ok":true' && ok "health 返回 ok:true" || bad "health 内容: $BODY"
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/)
expect_code "GET / 前端页面" 200 "$CODE"
curl -s http://127.0.0.1:8090/ | grep -q 'UTNixOS_Pro 管理面板' && ok "页面标题为 UTNixOS_Pro" || bad "页面标题未更新"

# 2. 登录
CODE=$(api -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/login \
  -H 'Content-Type: application/json' -d '{"username":"reimilia","password":"WrongPass"}')
expect_code "错误密码拒绝" 401 "$CODE"
CODE=$(api -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/login \
  -H 'Content-Type: application/json' -d '{"username":"root","password":"x"}')
expect_code "禁止 root 登录" 403 "$CODE"
CODE=$(api -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/login \
  -H 'Content-Type: application/json' -d '{"username":"reimilia","password":"TestPass123"}')
expect_code "正确密码登录（PAM）" 200 "$CODE"
ME=$(api http://127.0.0.1:8090/api/me)
echo "$ME" | grep -q '"user":"reimilia"' && ok "GET /api/me 返回 reimilia" || bad "/api/me: $ME"
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/api/me)
expect_code "无 cookie 访问 /api/me 拒绝" 401 "$CODE"

# 3. 跨站请求防护（Origin 不匹配）
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/logout \
  -H 'Origin: http://evil.example' -b /tmp/cj)
expect_code "跨站 POST 被拒" 403 "$CODE"

# 4. 状态与模块
ST=$(api http://127.0.0.1:8090/api/status)
echo "$ST" | grep -q '"hasFlake":true' && ok "status 识别 flake 配置目录" || bad "status: $ST"
echo "$ST" | grep -q '"configDir":"/etc/nixos"' && ok "status 配置目录正确" || bad "status: $ST"
MODS=$(api http://127.0.0.1:8090/api/modules)
echo "$MODS" | grep -q '"key":"desktop"' && ok "modules 含 desktop 组" || bad "modules 缺 desktop"
echo "$MODS" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['single']['desktop']['current']=='xfce', d['single']['desktop']; assert d['single']['boot']['current']=='grub-theme'; assert any(m['name']=='webui' and not m['enabled'] for m in d['multi']['system']['options']); assert len(d['other'])>0; print('modules 结构正确: desktop=xfce boot=grub-theme webui=off other=%d' % len(d['other']))" \
  && ok "modules 结构与当前配置一致" || bad "modules 结构异常"

# 5. 模块应用（切换到 kde + 开启 webui）
SEL='{"selection":{"desktop":"kde","boot":"grub-theme","locale":"en_US","input":"ibus","mirror":"ustc","userShell":"zsh","systemModules":["auto-update","clean","nix-command","zram","fonts","webui"],"advanced":[]}}'
RES=$(api -X POST http://127.0.0.1:8090/api/modules/apply -H 'Content-Type: application/json' -d "$SEL")
echo "$RES" | grep -q '"changed"' && ok "modules/apply 返回修改摘要" || bad "modules/apply: $RES"
grep -q '^[[:space:]]*\./modules/desktop/kde\.nix' /etc/nixos/configuration.nix && ok "configuration.nix 已切到 kde" || bad "configuration.nix 未切换"
grep -q '^[[:space:]]*\./modules/system/webui\.nix' /etc/nixos/configuration.nix && ok "configuration.nix 已开启 webui" || bad "webui 未开启"
grep -q '^DESKTOP=kde$' /etc/nixos/.utnixos-pro-selection && ok ".utnixos-pro-selection 已写入（与 TUI 共用）" || bad "状态文件未写入"

# 6. 软件包（声明式）
PKG=$(api http://127.0.0.1:8090/api/packages)
echo "$PKG" | grep -q '"htop"' && ok "packages 读到声明式包 htop" || bad "packages: $PKG"
RES=$(api -X POST http://127.0.0.1:8090/api/packages/declarative -H 'Content-Type: application/json' -d '{"attr":"ripgrep"}')
echo "$RES" | grep -q '"list"' && ok "声明式添加 ripgrep" || bad "declarative: $RES"
grep -q 'ripgrep' /etc/nixos/host/packages.nix && ok "host/packages.nix 已写入 ripgrep" || bad "host/packages.nix 未更新"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/packages/declarative \
  -H 'Content-Type: application/json' -b /tmp/cj -d '{"attr":"../etc/passwd"}')
expect_code "非法包名被拒绝" 400 "$CODE"
RES=$(api -X POST http://127.0.0.1:8090/api/packages/validate -H 'Content-Type: application/json' -d '{"attr":"htop"}')
echo "$RES" | grep -q '"ok":true' && ok "包属性校验 htop 通过" || bad "validate: $RES"

# 7. generations / 审计
GEN=$(api http://127.0.0.1:8090/api/generations)
echo "$GEN" | python3 -c "import json,sys; d=json.load(sys.stdin); assert len(d['generations'])==3, d; assert d['current']==21; print('generations: 3 条, current=21')" \
  && ok "generations 解析正常" || bad "generations: $GEN"
AUD=$(api 'http://127.0.0.1:8090/api/audit?limit=50')
echo "$AUD" | grep -q 'login' && ok "审计日志记录登录" || bad "审计无登录记录"
[ -f /var/lib/utnixos-pro-webui/audit.log ] && ok "审计文件在 /var/lib/utnixos-pro-webui" || bad "审计文件缺失"

# 8. 后台任务（rebuild + SSE 流）
OP=$(api -X POST http://127.0.0.1:8090/api/ops -H 'Content-Type: application/json' -d '{"type":"rebuild"}')
OPID=$(echo "$OP" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
[ -n "$OPID" ] && ok "启动 rebuild 任务（id=$OPID）" || bad "启动任务失败: $OP"
sleep 1
STREAM=$(timeout 10 curl -s -N -b /tmp/cj "http://127.0.0.1:8090/api/ops/$OPID/stream")
echo "$STREAM" | grep -q 'event: status' && ok "op SSE 流收到 status 事件" || bad "op 流异常: $(echo "$STREAM" | head -2)"
echo "$STREAM" | grep -q 'event: line' && ok "op SSE 流收到输出行" || bad "op 流无输出行"

# 9. 日志
LOGS=$(api 'http://127.0.0.1:8090/api/logs?lines=50')
echo "$LOGS" | grep -q 'journal' && ok "GET /api/logs 正常" || bad "logs: $LOGS"
UNITS=$(api http://127.0.0.1:8090/api/logs/units)
echo "$UNITS" | grep -q 'foo.service' && ok "GET /api/logs/units 正常" || bad "units: $UNITS"

# 10. 登录限速（1 分钟 5 次失败）
RATE=0
for i in 1 2 3 4 5; do
  CODE=$(api -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8090/api/login \
    -H 'Content-Type: application/json' -d '{"username":"reimilia","password":"bad"}')
  [ "$CODE" = "429" ] && RATE=$((RATE+1))
done
[ "$RATE" -ge 1 ] && ok "登录限速生效（连续失败后被 429 拦截）" || bad "限速未生效"

# 11. 前端静态资源
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/app.js)
expect_code "GET /app.js" 200 "$CODE"
curl -s http://127.0.0.1:8090/app.js | grep -q 'UTNixOS_Pro 管理面板' && ok "前端 JS 品牌已更新" || bad "app.js 品牌未更新"

kill $WEBUI_PID 2>/dev/null
echo ""
echo "=========================================="
echo "WebUI 测试结果：PASS=$PASS FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
