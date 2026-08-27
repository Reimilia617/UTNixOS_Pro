#!/usr/bin/env bash
# ============================================================================
# UTNixOS_Pro 脚本功能容器测试（在容器内运行）
#
# 在 Debian 容器中模拟 NixOS live 环境：
#   - /mnt 挂载为 tmpfs（模拟 live 安装挂载点）
#   - nixos-install / nixos-generate-config / nixos-rebuild / nix-env 等
#     用 stub 脚本代替（只记录调用参数，不真正构建系统）
#   - 用 `script` 分配 PTY 驱动交互式菜单（read 需要 /dev/tty）
#
# 覆盖：
#   1. install.sh install  默认选项全新安装流程（菜单→改配置→部署→nixos-install）
#   2. install.sh install  自定义选项（systemd-boot/gnome/zh_CN/fcitx5/tuna/fish/vm-debug/secrets）
#   2.5 install.sh install GRUB(BIOS)+主题+目标磁盘（BIOS 引导修复回归）
#   3. install.sh menu     已装系统换模块（kde + 重建）
#   4. install.sh update   同步代码 + 保留机器文件 + 重放选择 + 重建
#   5. install.sh rollback 回滚到指定 generation（stub profile）
#   6. install.sh 引导模式（curl|bash 等价路径：从 GIT_URL 拉取模块）
#   7. auto 默认路由：live → 安装界面；已装系统（即使 PATH 有 nixos-install）→ 管理面板
# ============================================================================
set -u
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }

# 固定为中文，使下方针对中文输出的断言保持稳定（双语实现见 script/lib/i18n.sh）
export UTNIXOS_PRO_LANG=zh

# 容器内 git 常因目录所有权被安全策略拦截，统一放行本测试用目录
git config --global --add safe.directory '*' 2>/dev/null || true

# 稳定驱动交互式脚本：脚本通过 read 从 /dev/tty（PTY）读取输入。
# 一次灌入整串会被 PTY 行缓冲吞掉末尾输入（尤其确认 y），所以把每一行
# 作为独立参数、逐行 printf + 延时送出，确保子进程逐个 read 到。
pty_in() { # pty_in <命令> <输出文件> <line1> [line2...]  （空串参数=空行）
  local cmd="$1" out="$2"; shift 2
  { for ln in "$@"; do printf '%s\n' "$ln"; sleep 0.35; done; sleep 0.6; } \
    | script -qec "$cmd" /dev/null >"$out" 2>&1
}
check() { # check <描述> <grep 模式> <文件>
  if grep -qE "$2" "$3"; then ok "$1"; else bad "$1（$3 中未找到 $2）"; fi
}
check_not() {
  if grep -qE "$2" "$3"; then bad "$1（$3 中不应出现 $2）"; else ok "$1"; fi
}

# ---------- 准备 stub ----------
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
cat > /usr/local/bin/nix <<'STUB'
#!/bin/bash
echo "[stub] nix $*" >> /tmp/stub.log
STUB
cat > /usr/local/bin/nix-collect-garbage <<'STUB'
#!/bin/bash
echo "[stub] nix-collect-garbage $*" >> /tmp/stub.log
STUB
chmod +x /usr/local/bin/nixos-generate-config /usr/local/bin/nixos-install \
  /usr/local/bin/nixos-rebuild /usr/local/bin/nix-env /usr/local/bin/nix \
  /usr/local/bin/nix-collect-garbage
rm -f /tmp/stub.log

# 回滚需要 /run/current-system/bin/switch-to-configuration
mkdir -p /run/current-system/bin
cat > /run/current-system/bin/switch-to-configuration <<'STUB'
#!/bin/bash
echo "[stub] switch-to-configuration $*" >> /tmp/stub.log
STUB
chmod +x /run/current-system/bin/switch-to-configuration

echo ""
echo "========== 测试 1：install.sh install（默认选项） =========="
INPUT=()   # 全部默认 + 确认安装（新菜单顺序：引导→主题→桌面→…）
pty_in "bash /repo/install.sh install" /tmp/t1.out '' '' '' '' '' '' '' '' '' '' 'y'
echo "--- 输出片段 ---"; grep -E "安装完成|✓|✗|错误" /tmp/t1.out | head -8
CFG=/mnt/etc/nixos/configuration.nix
[ -f "$CFG" ] && ok "configuration.nix 已部署到 /mnt/etc/nixos" || bad "configuration.nix 未部署"
[ -f /mnt/etc/nixos/.utnixos-pro-selection ] && ok ".utnixos-pro-selection 已生成" || bad ".utnixos-pro-selection 未生成"
[ -f /mnt/etc/nixos/hardware-configuration.nix ] && ok "hardware-configuration.nix 已生成" || bad "hardware-configuration.nix 未生成"
[ -f /mnt/etc/nixos/script/main.sh ] && ok "script/ 模块已随配置部署" || bad "script/ 未部署"
[ -f /mnt/etc/nixos/host/grub-device.nix ] && ok "host/grub-device.nix 已部署" || bad "host/grub-device.nix 未部署"
check "桌面默认 xfce 启用"        '^[[:space:]]*\./modules/desktop/xfce\.nix' "$CFG"
check_not "桌面 gnome 未启用"     '^[[:space:]]*[^#]*\./modules/desktop/gnome\.nix' "$CFG"
check "引导默认 GRUB(UEFI)"       '^[[:space:]]*\./modules/boot/grub\.nix' "$CFG"
check "GRUB 主题默认启用"         '^[[:space:]]*\./modules/boot/grub-theme\.nix' "$CFG"
check_not "grub-bios 默认关闭"    '^[[:space:]]*[^#]*\./modules/boot/grub-bios\.nix' "$CFG"
check "语言默认 en_US"            '^[[:space:]]*\./modules/locale/en_US\.nix' "$CFG"
check "输入法默认 ibus"           '^[[:space:]]*\./modules/input/ibus\.nix' "$CFG"
check "镜像默认 ustc"             '^[[:space:]]*\./modules/mirrors/ustc\.nix' "$CFG"
check "Shell 默认 zsh"            '^[[:space:]]*\./modules/shell/zsh\.nix' "$CFG"
for m in auto-update clean nix-command zram fonts webui; do
  check "系统模块 $m 默认启用"    "^[[:space:]]*\./modules/system/$m\.nix" "$CFG"
done
check_not "secrets 默认关闭"      '^[[:space:]]*[^#]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=zsh"    '^[[:space:]]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=xfce$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=xfce" || bad "状态文件 DESKTOP 错误"
grep -q '^BOOT=grub-uefi$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=grub-uefi" || bad "状态文件 BOOT 错误"
grep -q '^GRUB_THEME=yes$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 GRUB_THEME=yes" || bad "状态文件 GRUB_THEME 错误"
grep -q '^USERSHELL=zsh$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=zsh" || bad "状态文件 USERSHELL 错误"
grep -q 'nixos-install --flake /mnt/etc/nixos#reimilia --option substituters' /tmp/stub.log \
  && ok "nixos-install 以 flake+镜像源 调用" || bad "nixos-install 调用参数不符: $(grep nixos-install /tmp/stub.log)"

echo ""
echo "========== 测试 2：install.sh install（自定义选项） =========="
# 引导 systemd-boot(3)（无主题/磁盘问题）→ 桌面 gnome(2) → zh_CN(2) → fcitx5(2) → tuna(2) → fish(3)
# → 系统模块 vm-debug(8)（webui 已默认开）→ 进阶 secrets(1)
INPUT=()
pty_in "bash /repo/install.sh install" /tmp/t2.out '3' '2' '2' '2' '2' '3' '8' '' '1' '' 'y'
grep -E "安装完成|✓|✗" /tmp/t2.out | head -6
check "自定义桌面 gnome 启用"     '^[[:space:]]*\./modules/desktop/gnome\.nix' "$CFG"
check_not "xfce 被注释"           '^[[:space:]]*[^#]*\./modules/desktop/xfce\.nix' "$CFG"
check "systemd-boot 启用"         '^[[:space:]]*\./modules/boot/systemd-boot\.nix' "$CFG"
check_not "grub 被注释"           '^[[:space:]]*[^#]*\./modules/boot/grub\.nix' "$CFG"
check_not "grub 主题被注释"       '^[[:space:]]*[^#]*\./modules/boot/grub-theme\.nix' "$CFG"
check "zh_CN 启用"                '^[[:space:]]*\./modules/locale/zh_CN\.nix' "$CFG"
check "fcitx5 启用"               '^[[:space:]]*\./modules/input/fcitx5\.nix' "$CFG"
check "tuna 启用"                 '^[[:space:]]*\./modules/mirrors/tuna\.nix' "$CFG"
check "fish 启用"                 '^[[:space:]]*\./modules/shell/fish\.nix' "$CFG"
check "webui 启用"                '^[[:space:]]*\./modules/system/webui\.nix' "$CFG"
check "vm-debug 启用"             '^[[:space:]]*\./modules/system/vm-debug\.nix' "$CFG"
check "secrets 启用"              '^[[:space:]]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=fish"   '^[[:space:]]*\./shell/fish\.nix' /mnt/etc/nixos/home/home-manager.nix
check_not "home-manager zsh 关闭" '^[[:space:]]*[^#]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=gnome$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=gnome" || bad "状态文件 DESKTOP 错误"
grep -q '^BOOT=systemd-boot$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=systemd-boot" || bad "状态文件 BOOT 错误"
grep -q '^USERSHELL=fish$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=fish" || bad "状态文件 USERSHELL 错误"
grep -q '^SYSTEM_MODULES=.*webui' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 含 webui" || bad "状态文件 不含 webui"
grep -q '^ADVANCED=secrets' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 含 secrets" || bad "状态文件 不含 secrets"

echo ""
echo "========== 测试 2.5：install.sh install（GRUB BIOS + 主题 + 目标磁盘） =========="
# BUG 回归：BIOS 启动必须能选 GRUB(BIOS) 并写入目标磁盘
# （旧版只有 grub.nix(efiSupport+nodev) 无法在 BIOS/MBR 上安装引导器）
# 引导 grub-bios(2) → 主题(回车=开) → 磁盘手动输入 /dev/sda → 其余默认
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
INPUT=()
pty_in "bash /repo/install.sh install" /tmp/t25.out '2' '' '/dev/sda' '' '' '' '' '' '' '' 'y'
grep -E "安装完成|GRUB 目标磁盘|✓|✗" /tmp/t25.out | head -6
check "grub-bios 启用"            '^[[:space:]]*\./modules/boot/grub-bios\.nix' "$CFG"
check_not "grub(UEFI) 关闭"       '^[[:space:]]*[^#]*\./modules/boot/grub\.nix' "$CFG"
check "grub-bios 主题启用"        '^[[:space:]]*\./modules/boot/grub-theme\.nix' "$CFG"
grep -q 'boot.loader.grub.device = "/dev/sda"' /mnt/etc/nixos/host/grub-device.nix \
  && ok "host/grub-device.nix 写入 /dev/sda" || bad "host/grub-device.nix 未写入设备"
grep -q '^BOOT=grub-bios$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=grub-bios" || bad "状态文件 BOOT 错误"
grep -q '^GRUB_THEME=yes$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 GRUB_THEME=yes" || bad "状态文件 GRUB_THEME 错误"
grep -q '^GRUB_DEVICE=/dev/sda$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 GRUB_DEVICE=/dev/sda" || bad "状态文件 GRUB_DEVICE 错误"

echo ""
echo "========== 测试 3：install.sh menu（已装系统换模块） =========="
rm -rf /etc/nixos && mkdir -p /etc/nixos
rsync -a --exclude '.git' --exclude 'hardware-configuration.nix' /repo/ /etc/nixos/
# 模拟已安装系统：机器专属文件（与仓库默认内容不同，用于验证 update 时被保留）
echo '# MACHINE hardware' > /etc/nixos/hardware-configuration.nix
printf '# machine-local packages\nhtop\n' > /etc/nixos/host/packages.nix
# 先把"仓库默认状态"提交成初始 generation（此时 configuration.nix 是默认 xfce）
git -C /etc/nixos init -q -b main
git -C /etc/nixos config user.email test@test && git -C /etc/nixos config user.name test
git -C /etc/nixos add -A && git -C /etc/nixos commit -qm init
git init -q --bare /tmp/origin.git
git -C /etc/nixos remote add origin /tmp/origin.git
git -C /etc/nixos push -q origin main
# 本地修改机器文件（模拟 Web 面板/手工改动，提交里没有这些内容）
echo '# MACHINE hardware v2' > /etc/nixos/hardware-configuration.nix
printf '# machine-local packages v2\nhtop\nripgrep\n' > /etc/nixos/host/packages.nix
# 桌面 kde(3)，引导/主题等其余默认（新菜单顺序：引导→主题→桌面）
INPUT=()   # 引导(回车=grub-uefi) 主题(回车=开) 桌面 kde(3) 其余默认
pty_in "bash /etc/nixos/install.sh menu" /tmp/t3.out '' '' '3' '' '' '' '' '' '' 'y'
grep -E "模块切换完成|✓|✗" /tmp/t3.out | head -5
check "menu 切换到 kde"          '^[[:space:]]*\./modules/desktop/kde\.nix' /etc/nixos/configuration.nix
check_not "menu 后 xfce 关闭"    '^[[:space:]]*[^#]*\./modules/desktop/xfce\.nix' /etc/nixos/configuration.nix
grep -q '^DESKTOP=kde$' /etc/nixos/.utnixos-pro-selection && ok "menu 状态文件 DESKTOP=kde" || bad "menu 状态文件错误"
grep -q 'nixos-rebuild switch --flake /etc/nixos#reimilia' /tmp/stub.log \
  && ok "menu 后 nixos-rebuild 以 flake 调用" || bad "menu 未触发 nixos-rebuild"

echo ""
echo "========== 测试 4：install.sh update（同步代码+保留机器文件+重建） =========="
# 更新前记录机器文件内容（v2 版本）
BEFORE_HW=$(cat /etc/nixos/hardware-configuration.nix)
BEFORE_PKG=$(cat /etc/nixos/host/packages.nix)
BEFORE_GDEV=$(cat /etc/nixos/host/grub-device.nix 2>/dev/null || true)
INPUT=()   # 不重新选择模块
pty_in "bash /etc/nixos/install.sh update" /tmp/t4.out 'n'
grep -E "系统更新完成|✓|✗" /tmp/t4.out | head -5
[ "$(cat /etc/nixos/hardware-configuration.nix)" = "$BEFORE_HW" ] && ok "hardware-configuration.nix 被保留" || bad "hardware-configuration.nix 丢失/被覆盖"
[ "$(cat /etc/nixos/host/packages.nix)" = "$BEFORE_PKG" ] && ok "host/packages.nix 被保留" || bad "host/packages.nix 丢失/被覆盖"
[ "$(cat /etc/nixos/host/grub-device.nix 2>/dev/null || true)" = "$BEFORE_GDEV" ] && ok "host/grub-device.nix 被保留" || bad "host/grub-device.nix 丢失/被覆盖"
[ -f /etc/nixos/.utnixos-pro-selection ] && ok "选择状态文件被保留" || bad "选择状态文件丢失"
check "update 后重放选择 kde"    '^[[:space:]]*\./modules/desktop/kde\.nix' /etc/nixos/configuration.nix
N=$(grep -c 'nixos-rebuild switch --flake /etc/nixos#reimilia' /tmp/stub.log)
[ "$N" -ge 2 ] && ok "update 触发了 nixos-rebuild（共 $N 次）" || bad "update 未触发 nixos-rebuild"

echo ""
echo "========== 测试 5：install.sh rollback（回滚到指定 generation） =========="
mkdir -p /tmp/fakeprof
export UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
INPUT=()   # 回滚到 generation 22
pty_in "bash /etc/nixos/install.sh rollback" /tmp/t5.out '22'
grep -E "回滚完成|✓|✗" /tmp/t5.out | head -3
grep -q 'nix-env --switch-generation 22 -p /tmp/fakeprof' /tmp/stub.log && ok "切换到 generation 22" || bad "未调用 switch-generation 22"
grep -q 'switch-to-configuration switch' /tmp/stub.log && ok "激活 generation" || bad "未调用 switch-to-configuration"
# 空输入分支：回滚到上一个版本
INPUT=()   # 回车=回滚到上一个版本
pty_in "bash /etc/nixos/install.sh rollback" /tmp/t5b.out ''
grep -q 'nixos-rebuild switch --rollback' /tmp/stub.log && ok "默认回滚分支调用 nixos-rebuild --rollback" || bad "默认回滚分支未触发"

echo ""
echo "========== 测试 6：引导模式（curl|bash 等价：从 GIT_URL 拉取模块） =========="
mkdir -p /tmp/alone && cp /repo/install.sh /tmp/alone/install.sh
# help 模式：只验证拉取+路由
UTNIXOS_PRO_GIT_URL=file:///repo bash /tmp/alone/install.sh help >/tmp/t6.out 2>&1
grep -q "正在从 GitHub 获取 UTNixOS_Pro 脚本" /tmp/t6.out && ok "引导模式从 GIT_URL 拉取代码" || bad "引导模式未拉取"
grep -q "curl 方式安装" /tmp/t6.out && ok "help 路由正常" || bad "help 输出异常"
# 双语：英文环境应输出英文帮助
UTNIXOS_PRO_LANG=en UTNIXOS_PRO_GIT_URL=file:///repo bash /tmp/alone/install.sh help >/tmp/t6en.out 2>&1
grep -q "Usage:" /tmp/t6en.out && ok "双语：英文环境（UTNIXOS_PRO_LANG=en）输出英文帮助" || bad "英文环境未输出英文帮助"
# --rollback 走引导模式完整回滚（保险方案路径）
INPUT=()   # 回滚到 generation 22
export UTNIXOS_PRO_GIT_URL=file:///repo UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
pty_in "bash /tmp/alone/install.sh --rollback" /tmp/t6b.out '22'
grep -q '回滚完成' /tmp/t6b.out && ok "curl|bash --rollback 保险回滚可用" || bad "引导回滚失败: $(tail -3 /tmp/t6b.out)"

echo ""
echo "========== 测试 7：auto 默认路由（live → 安装 / 已装 → 管理面板） =========="
# BUG 回归（ut 打不开管理面板）：已装 NixOS 的 PATH 里同样有 nixos-install
# （nixos-install-tools 是系统默认包），所以「nixos-install 在 PATH」不能作为 live 标志。
# 正确判据（见 main.sh is_live_env）：
#   - 已装 = /nix/var/nix/profiles/system 系统 profile 存在 且 /etc/nixos/hardware-configuration.nix 存在
#   - live = 根文件系统是 overlay（live ISO）或默认用户 nixos 存在（注意：live ISO 也有 /etc/nixos！）
rm -rf /mnt/etc /etc/nixos /nix/var/nix/profiles/system    # 清空现场：模拟 fresh live
mkdir -p /nix/var/nix/profiles
export UTNIXOS_PRO_TEST=1             # 阻止 source 时自动执行 main
# shellcheck disable=SC1091
source /repo/script/main.sh
# source 会加载 util.sh 的同名 ok()/bad()（输出函数），覆盖了测试用的计数 helper，需重新声明
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
cmd_install()   { echo "ROUTED_TO=INSTALL";   return; }
cmd_dashboard() { echo "ROUTED_TO=DASHBOARD"; return; }

# 场景 1：live ISO（容器 root 是 overlay = live 硬标志；nixos 用户也建一个）→ 安装界面
id nixos >/dev/null 2>&1 || useradd -M nixos
ROUTE="$(main)"
[ "$ROUTE" = "ROUTED_TO=INSTALL" ] \
  && ok "live（root 是 overlay + nixos 用户，即使 PATH 有 nixos-install）auto → 安装界面" \
  || bad "live 环境 auto 路由错误: $ROUTE"

# 场景 2：已装系统（系统 profile + /etc/nixos/hardware-configuration.nix 存在，
# PATH 里仍有 nixos-install！）→ 管理面板。这是「ut 打不开管理面板」的核心回归用例。
mkdir -p /etc/nixos
ln -sf /nix/store/fake-system /nix/var/nix/profiles/system
printf '{ fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; }; }' \
  > /etc/nixos/hardware-configuration.nix
ROUTE="$(main)"
[ "$ROUTE" = "ROUTED_TO=DASHBOARD" ] \
  && ok "已装系统（有系统 profile + 硬件配置，PATH 仍有 nixos-install）auto → 管理面板" \
  || bad "已装系统 auto 路由错误: $ROUTE"

# 场景 3：已装系统上又挂载全新 /mnt 并生成硬件配置（重装）→ 安装界面
mkdir -p /mnt/etc/nixos
printf '{ fileSystems."/" = { device = "/dev/vda2"; fsType = "ext4"; }; }' \
  > /mnt/etc/nixos/hardware-configuration.nix
ROUTE="$(main)"
[ "$ROUTE" = "ROUTED_TO=INSTALL" ] \
  && ok "已装系统 + /mnt 新系统（重装）auto → 安装界面" \
  || bad "重装场景 auto 路由错误: $ROUTE"

# 清理现场：移除模拟的系统 profile /etc/nixos /mnt 与 nixos 用户
rm -rf /etc/nixos /mnt/etc /nix/var/nix/profiles
userdel nixos 2>/dev/null || true
unset UTNIXOS_PRO_TEST

echo ""
echo "=========================================="
echo "脚本测试结果：PASS=$PASS FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
