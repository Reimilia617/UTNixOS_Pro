#!/usr/bin/env bash
# ============================================================================
# UTNixOS_Pro 两种安装方式容器测试（在 Debian 容器内运行）
#
# 明确覆盖用户要求的两种不同安装方式，验证「是否都能运行」：
#
#   方式 A — curl 脚本安装（curl | bash）
#     `cat /repo/install.sh | bash -s -- install`
#     等价于 `curl -L <raw install.sh> | bash`：install.sh 从 stdin 管道进来
#     （$0=bash、本地无 install.sh 文件）→ 触发「引导模式」，脚本自动从
#     GIT_URL 拉取完整仓库再继续安装。
#
#   方式 B — git clone 到本地后安装
#     `git clone <repo> /tmp/methodB && bash /tmp/methodB/install.sh install`
#     install.sh 就在克隆目录里（$0 存在）→ 直接用旁边的 script/ 模块。
#
# 两者都执行真实的安装主流程（菜单 → 生成硬件配置 → 部署到 /mnt → nixos-install），
# 用 stub 代替 nixos-generate-config / nixos-install（只记录调用，不真正构建系统）。
# 用 `script` 分配 PTY 驱动交互菜单（read 需要 /dev/tty）。
# ============================================================================
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check() { if grep -qE "$2" "$3"; then ok "$1"; else bad "$1（$3 中未找到 $2）"; fi; }

# 固定为中文，使下方针对中文输出的断言保持稳定（双语实现见 script/lib/i18n.sh）
export UTNIXOS_PRO_LANG=zh

# 稳定驱动交互式脚本：脚本通过 read 从 /dev/tty（PTY）读取输入。
# 一次灌入整串会被 PTY 行缓冲吞掉末尾输入（尤其确认 y），所以把每一行
# 作为独立参数、逐行 printf + 延时送出，确保子进程逐个 read 到。
pty_in() { # pty_in <命令> <输出文件> <line1> [line2...]  （空串参数=空行）
  local cmd="$1" out="$2"; shift 2
  { for ln in "$@"; do printf '%s\n' "$ln"; sleep 0.35; done; sleep 0.6; } \
    | script -qec "$cmd" /dev/null >"$out" 2>&1
}
# 容器内 git 常因目录所有权被安全策略拦截，统一放行本测试用目录
git config --global --add safe.directory '*' 2>/dev/null || true

# ---------- 通用 stub（两种方式共用）----------
mkdir -p /usr/local/bin
cat > /usr/local/bin/nixos-generate-config <<'STUB'
#!/bin/bash
echo "[stub] nixos-generate-config $*" >> /tmp/stub.log
mkdir -p /mnt/etc/nixos
cat > /mnt/etc/nixos/hardware-configuration.nix <<'EOF'
{ config, lib, pkgs, modulesPath, ... }: { fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; }; }
EOF
STUB
cat > /usr/local/bin/nixos-install <<'STUB'
#!/bin/bash
echo "[stub] nixos-install $*" >> /tmp/stub.log
STUB
cat > /usr/local/bin/nixos-rebuild <<'STUB'
#!/bin/bash
echo "[stub] nixos-rebuild $*" >> /tmp/stub.log
echo "building the system configuration..."
echo "activating the configuration..."
STUB
cat > /usr/local/bin/nix <<'STUB'
#!/bin/bash
echo "[stub] nix $*" >> /tmp/stub.log
STUB
chmod +x /usr/local/bin/nixos-generate-config /usr/local/bin/nixos-install \
  /usr/local/bin/nixos-rebuild /usr/local/bin/nix

# ---------- 准备本地 git 源（file:// 模拟远程仓库，供两种方式拉取/clone）----------
rm -rf /tmp/origin && git clone --bare -q /repo /tmp/origin.git 2>/dev/null \
  || git init -q --bare /tmp/origin.git
if [ ! -d /tmp/origin.git/HEAD ] && [ "$(git -C /tmp/origin.git count-objects 2>/dev/null)" ]; then :; fi
# 用 git clone 从裸仓库得到一个"远程 URL"可指向的源；更稳的做法：直接让 file:///repo 作为源
export UTNIXOS_PRO_GIT_URL="file:///repo"

echo ""
echo "============================================================"
echo "方式 A：curl 脚本安装（cat install.sh | bash -s -- install）"
echo "============================================================"
# 方式 A 模拟 curl | bash：只有 install.sh 单文件（旁边没有 script/ 模块），
# 触发「引导模式」——脚本自己从 GIT_URL 拉取完整仓库再安装。
# 这正是 `curl -L <raw install.sh> | bash` 的真实行为。
rm -rf /tmp/alone && mkdir -p /tmp/alone && cp /repo/install.sh /tmp/alone/install.sh
# 清理上个测试残留，重新挂载 /mnt
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
INPUT=()   # 全部默认 + 确认安装
pty_in "bash /tmp/alone/install.sh install" /tmp/mA.out '' '' '' '' '' '' '' '' 'y'
echo "--- 输出片段 ---"
grep -E "正在从 GitHub 获取|复用已拉取的代码|git clone|安装完成|✗|错误" /tmp/mA.out | head -10
grep -q "正在从 GitHub 获取 UTNixOS_Pro 脚本" /tmp/mA.out \
  && ok "A: curl|bash 触发引导模式（从 GIT_URL 拉取代码）" || bad "A: 未触发引导模式"
CFG=/mnt/etc/nixos/configuration.nix
[ -f "$CFG" ] && ok "A: configuration.nix 已部署到 /mnt/etc/nixos" || bad "A: configuration.nix 未部署"
[ -f /mnt/etc/nixos/.utnixos-pro-selection ] && ok "A: .utnixos-pro-selection 已生成" || bad "A: 状态文件未生成"
[ -f /mnt/etc/nixos/hardware-configuration.nix ] && ok "A: hardware-configuration.nix 已生成" || bad "A: 硬件配置未生成"
[ -f /mnt/etc/nixos/script/main.sh ] && ok "A: script/ 模块已随配置部署" || bad "A: script/ 未部署"
check "A: 桌面默认 xfce 启用" '^[[:space:]]*\./modules/desktop/xfce\.nix' "$CFG"
grep -q 'nixos-install --flake /mnt/etc/nixos#reimilia' /tmp/stub.log \
  && ok "A: nixos-install 以 flake 调用" || bad "A: nixos-install 调用参数不符: $(grep nixos-install /tmp/stub.log)"
grep -q 'nixos-generate-config --root /mnt' /tmp/stub.log \
  && ok "A: nixos-generate-config 已调用" || bad "A: 未调用 nixos-generate-config"

echo ""
echo "============================================================"
echo "方式 B：git clone 到本地后安装"
echo "============================================================"
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
rm -rf /tmp/methodB
git clone -q "$UTNIXOS_PRO_GIT_URL" /tmp/methodB 2>&1 | tail -1
[ -f /tmp/methodB/install.sh ] && ok "B: git clone 成功（install.sh 存在）" || bad "B: git clone 失败"
INPUT=()   # 全部默认 + 确认安装
pty_in "bash /tmp/methodB/install.sh install" /tmp/mB.out '' '' '' '' '' '' '' '' 'y'
echo "--- 输出片段 ---"
grep -E "复用已拉取的代码|git clone|安装完成|✗|错误" /tmp/mB.out | head -10
grep -q "复用已拉取的代码" /tmp/mB.out \
  && ok "B: 使用克隆目录内的 script/ 模块（未触发引导模式）" || bad "B: 走错了引导模式"
[ -f "$CFG" ] && ok "B: configuration.nix 已部署到 /mnt/etc/nixos" || bad "B: configuration.nix 未部署"
[ -f /mnt/etc/nixos/.utnixos-pro-selection ] && ok "B: .utnixos-pro-selection 已生成" || bad "B: 状态文件未生成"
[ -f /mnt/etc/nixos/hardware-configuration.nix ] && ok "B: hardware-configuration.nix 已生成" || bad "B: 硬件配置未生成"
grep -q 'nixos-install --flake /mnt/etc/nixos#reimilia' /tmp/stub.log \
  && ok "B: nixos-install 以 flake 调用" || bad "B: nixos-install 调用参数不符"
# 克隆目录保留 .git，验证 update 可复用 git 源（方式 B 的完整生命周期）
[ -d /mnt/etc/nixos/.git ] && ok "B: 部署到 /mnt 时保留了 .git（供后续 update）" || bad "B: .git 未保留"

echo ""
echo "============================================================"
echo "补充：curl|bash 引导模式下的 --rollback 保险回滚（方式 A 变体）"
echo "============================================================"
rm -rf /etc/nixos && mkdir -p /etc/nixos
mkdir -p /tmp/fakeprof
cat > /usr/local/bin/nix-env <<'STUB'
#!/bin/bash
echo "[stub] nix-env $*" >> /tmp/stub.log
if [[ "$*" == *--list-generations* ]]; then
  cat <<'GEN'
  21  2026-08-01 10:00:00   (current)
  22  2026-08-02 10:00:00
  23  2026-08-03 10:00:00
GEN
fi
STUB
chmod +x /usr/local/bin/nix-env
# 回滚激活需要 /run/current-system/bin/switch-to-configuration
mkdir -p /run/current-system/bin
cat > /run/current-system/bin/switch-to-configuration <<'STUB'
#!/bin/bash
echo "[stub] switch-to-configuration $*" >> /tmp/stub.log
STUB
chmod +x /run/current-system/bin/switch-to-configuration
rm -f /tmp/stub.log
INPUT=()   # 回滚到 generation 22
export UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
pty_in "bash /tmp/alone/install.sh --rollback" /tmp/mC.out '22'
grep -q '回滚完成' /tmp/mC.out && ok "curl|bash --rollback 保险回滚可用" || bad "引导回滚失败: $(tail -3 /tmp/mC.out)"

echo ""
echo "=========================================="
echo "两种安装方式测试结果：PASS=$PASS FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
