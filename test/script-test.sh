#!/usr/bin/env bash
# ============================================================================
# UTNixOS_Pro 脚本功能容器测试（在容器内运行）
#
# 在 Debian 容器中模拟 NixOS live 环境：
#   - /mnt 挂载为 tmpfs（模拟 live 安装挂载点）
#   - nixos-install / nixos-generate-config / nixos-rebuild / nix-env 等
#     用 stub 脚本代替（只记录调用参数，不真正构建系统）
#   - 用 `script` 分配 PTY 驱动交互式脚本（read 需要 /dev/tty）
#
# 覆盖（install.sh 已收拢为单文件，只保留 安装/修复配置/UT紧急回滚）：
#   1. install.sh install  默认选项全新安装流程（菜单→改配置→部署→nixos-install）
#   2. install.sh install  自定义选项（systemd-boot/gnome/zh_CN/fcitx5/tuna/fish/vm-debug/secrets）
#   2.5 install.sh install GRUB(BIOS)+主题+目标磁盘（BIOS 引导修复回归）
#   3. 入口菜单（已装系统）：进入脚本可选 安装/修复配置/UT紧急回滚，含 ut 提示
#   4. install.sh repair   /etc/nixos 损坏时修复（保留机器文件，脚本/仓库单文件化）
#   5. install.sh rollback 回滚到指定 generation（stub profile，UT紧急回滚）
#   6. 引导/自包含：单文件独立目录即可运行（--rollback 无需拉取仓库）；双语检测
# ============================================================================
set -u
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }

# 固定为中文，使下方针对中文输出的断言保持稳定（双语见 install.sh 内嵌字典）
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

# ---------- 帮助 / 双语 / 自包含 ----------
echo ""
echo "========== 测试 0：help 双语 + TERM=linux 强制英文 =========="
UTNIXOS_PRO_LANG=zh bash /repo/install.sh help >/tmp/t0.out 2>&1
grep -q "用法：" /tmp/t0.out && ok "中文环境输出中文帮助" || bad "中文帮助缺失"
grep -q "UT紧急回滚" /tmp/t0.out && ok "帮助里包含 UT紧急回滚" || bad "帮助缺 rollback 说明"
UTNIXOS_PRO_LANG=en TERM=xterm-256color bash /repo/install.sh help >/tmp/t0en.out 2>&1
grep -q "Usage:" /tmp/t0en.out && ok "英文环境输出英文帮助" || bad "英文帮助缺失"
grep -q "UT Emergency Rollback" /tmp/t0en.out && ok "英文帮助含 Emergency Rollback" || bad "英文帮助缺 rollback"
# 关键防方块回归：虚拟控制台（TERM=linux）即使 LC_ALL=zh 也必须强制英文
TERM=linux LC_ALL=zh_CN.UTF-8 UTNIXOS_PRO_LANG= bash /repo/install.sh help >/tmp/t0tty.out 2>&1
grep -q "Usage:" /tmp/t0tty.out && ok "TERM=linux（虚拟控制台）强制英文，避免中文方块" || bad "TERM=linux 未强制英文: $(head -5 /tmp/t0tty.out)"

echo ""
echo "========== 测试 1：install.sh install（默认选项） =========="
# 新菜单顺序：引导→[主题]→桌面→语言→输入法→镜像→Shell→系统模块(多选)→进阶模块(多选)→确认
rm -rf /mnt/etc; mkdir -p /mnt/etc
INPUT=()   # 全部默认（webui 已内置不再询问）+ 确认安装
pty_in "bash /repo/install.sh install" /tmp/t1.out \
  '' '' '' '' '' '' '' '' '' '' '' 'y'   # 菜单9回车 + 用户名/密码默认各回车 + 确认
echo "--- 输出片段 ---"; grep -E "安装完成|✓|✗|错误" /tmp/t1.out | head -8
CFG=/mnt/etc/nixos/configuration.nix
[ -f "$CFG" ] && ok "configuration.nix 已部署到 /mnt/etc/nixos" || bad "configuration.nix 未部署"
[ -f /mnt/etc/nixos/.utnixos-pro-selection ] && ok ".utnixos-pro-selection 已生成" || bad ".utnixos-pro-selection 未生成"
[ -f /mnt/etc/nixos/hardware-configuration.nix ] && ok "hardware-configuration.nix 已生成" || bad "hardware-configuration.nix 未生成"
[ ! -d /mnt/etc/nixos/script ] && ok "仓库已单文件化：/etc/nixos 下没有 script/ 目录" || bad "script/ 目录不应再部署"
[ -f /mnt/etc/nixos/install.sh ] && ok "单文件 install.sh 已随配置部署" || bad "install.sh 未部署"
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
for m in auto-update clean nix-command zram fonts; do
  check "系统模块 $m 默认启用"    "^[[:space:]]*\./modules/system/$m\.nix" "$CFG"
done
check "内置 webui 始终启用"       '^[[:space:]]*\./modules/system/webui\.nix' "$CFG"
check "内置 ut 命令始终启用"      '^[[:space:]]*\./modules/system/ut\.nix' "$CFG"
check_not "secrets 默认关闭"      '^[[:space:]]*[^#]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=zsh"    '^[[:space:]]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=xfce$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=xfce" || bad "状态文件 DESKTOP 错误"
grep -q '^BOOT=grub-uefi$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=grub-uefi" || bad "状态文件 BOOT 错误"
grep -q '^GRUB_THEME=yes$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 GRUB_THEME=yes" || bad "状态文件 GRUB_THEME 错误"
grep -q '^USERSHELL=zsh$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=zsh" || bad "状态文件 USERSHELL 错误"
grep -q '^SYSTEM_MODULES=auto-update clean nix-command zram fonts$' /mnt/etc/nixos/.utnixos-pro-selection \
  && ok "状态文件 SYSTEM_MODULES 不含 webui（内置）" || bad "状态文件 SYSTEM_MODULES 错误: $(grep SYSTEM_MODULES /mnt/etc/nixos/.utnixos-pro-selection)"
grep -q 'nixos-install --flake /mnt/etc/nixos#reimilia --option substituters' /tmp/stub.log \
  && ok "nixos-install 以 flake+镜像源 调用" || bad "nixos-install 调用参数不符: $(grep nixos-install /tmp/stub.log)"

echo ""
echo "========== 测试 2：install.sh install（自定义选项） =========="
# 引导 systemd-boot(3)（无主题/磁盘问题）→ 桌面 gnome(2) → zh_CN(2) → fcitx5(2) → tuna(2) → fish(3)
# → 系统模块 vm-debug(7，webui 已内置不再出现在列表) → 进阶 secrets(1)
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
INPUT=()
pty_in "bash /repo/install.sh install" /tmp/t2.out \
  '3' '2' '2' '2' '2' '3' '7' '' '1' '' '' '' 'y'   # 末尾两个回车=用户名/密码默认
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
check "内置 webui 始终启用"       '^[[:space:]]*\./modules/system/webui\.nix' "$CFG"
check "内置 ut 命令始终启用"      '^[[:space:]]*\./modules/system/ut\.nix' "$CFG"
check "vm-debug 启用"             '^[[:space:]]*\./modules/system/vm-debug\.nix' "$CFG"
check "secrets 启用"              '^[[:space:]]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=fish"   '^[[:space:]]*\./shell/fish\.nix' /mnt/etc/nixos/home/home-manager.nix
check_not "home-manager zsh 关闭" '^[[:space:]]*[^#]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=gnome$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=gnome" || bad "状态文件 DESKTOP 错误"
grep -q '^BOOT=systemd-boot$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=systemd-boot" || bad "状态文件 BOOT 错误"
grep -q '^USERSHELL=fish$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=fish" || bad "状态文件 USERSHELL 错误"
! grep -q '^SYSTEM_MODULES=.*webui' /mnt/etc/nixos/.utnixos-pro-selection \
  && ok "状态文件 SYSTEM_MODULES 不含 webui" || bad "状态文件 不该含 webui"
grep -q '^ADVANCED=secrets' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 含 secrets" || bad "状态文件 不含 secrets"

echo ""
echo "========== 测试 2.7：install.sh install（自定义用户名 + 密码，sed 写回配置） =========="
# 账号自定义回归：用户名 sakuya + 密码 Remilia158!（两次输入一致后确认安装）
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
pty_in "bash /repo/install.sh install" /tmp/t27.out \
  '' '' '' '' '' '' '' '' '' 'sakuya' 'Remilia158!' 'Remilia158!' 'y'
grep -E "安装完成|已将用户名/密码写入配置|✓|✗" /tmp/t27.out | head -5
grep -q 'users.users.sakuya = {' /mnt/etc/nixos/modules/users/reimilia.nix \
  && ok "自定义用户名写入 modules/users/reimilia.nix" || bad "用户名未写入"
grep -q 'description = "sakuya";' /mnt/etc/nixos/modules/users/reimilia.nix \
  && ok "description 已同步为 sakuya" || bad "description 未同步"
grep -qE 'initialHashedPassword = "\\$6\\$' /mnt/etc/nixos/modules/users/reimilia.nix \
  && ok "密码以 sha512 哈希写入" || bad "密码哈希未写入"
! grep -q 'kD9mMW0kEEjXfxxa' /mnt/etc/nixos/modules/users/reimilia.nix \
  && ok "默认密码哈希已被替换" || bad "旧哈希仍在"
grep -q 'home-manager.users.sakuya' /mnt/etc/nixos/flake.nix \
  && ok "flake.nix home-manager.users 同步为 sakuya" || bad "flake.nix 未同步"
grep -q 'home.username = "sakuya";' /mnt/etc/nixos/home/home-manager.nix \
  && ok "home-manager username=sakuya" || bad "home.username 未改"
grep -q 'home.homeDirectory = "/home/sakuya";' /mnt/etc/nixos/home/home-manager.nix \
  && ok "homeDirectory=/home/sakuya" || bad "homeDirectory 未改"
grep -q 'user = "sakuya";' /mnt/etc/nixos/modules/system/nopwdtodesktop.nix \
  && ok "免密自动登录用户同步为 sakuya" || bad "nopwdtodesktop 未同步"
[ -f /mnt/etc/nixos/modules/users/reimilia.nix ] \
  && ok "用户模块文件名保持不变（仅内容改写）" || bad "用户模块丢失"

echo ""
echo "========== 测试 2.5：install.sh install（GRUB BIOS + 主题 + 目标磁盘） =========="
# BUG 回归：BIOS 启动必须能选 GRUB(BIOS) 并写入目标磁盘
# 引导 grub-bios(2) → 主题(回车=开) → 磁盘手动输入 /dev/sda → 其余默认
rm -f /tmp/stub.log; rm -rf /mnt/etc; mkdir -p /mnt/etc
INPUT=()
pty_in "bash /repo/install.sh install" /tmp/t25.out \
  '2' '' '/dev/sda' '' '' '' '' '' '' '' '' '' 'y'   # 主题/磁盘后 桌面..进阶(7)+用户名/密码(2) 回车
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
echo "========== 测试 3：入口菜单（已装系统：安装/修复配置/UT紧急回滚 + ut 提示） =========="
# 模拟已装系统：系统 profile 存在 + /etc/nixos/hardware-configuration.nix 存在
rm -rf /etc/nixos && mkdir -p /etc/nixos /nix/var/nix/profiles
rsync -a --exclude '.git' /repo/ /etc/nixos/
ln -sf /nix/store/fake-system /nix/var/nix/profiles/system
printf '{ fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; }; }' \
  > /etc/nixos/hardware-configuration.nix
export UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
mkdir -p /tmp/fakeprof
# q → 退出：验证菜单展示了三项选择（安装/修复/UT紧急回滚）和 ut 提示
pty_in "bash /etc/nixos/install.sh" /tmp/t3q.out 'q'
grep -q "全新安装" /tmp/t3q.out && ok "入口菜单含「全新安装」" || bad "入口缺安装项"
grep -q "修复配置" /tmp/t3q.out && ok "入口菜单含「修复配置」" || bad "入口缺修复项"
grep -q "UT紧急回滚" /tmp/t3q.out && ok "入口菜单含「UT紧急回滚」" || bad "入口缺回滚项"
grep -q "运行  ut" /tmp/t3q.out && ok "入口提示 ut 打开 Web 管理面板" || bad "入口缺 ut 提示"
# 选 3 → UT紧急回滚，输入 generation 22
pty_in "bash /etc/nixos/install.sh" /tmp/t3.out '3' '22'
grep -q '回滚完成' /tmp/t3.out && ok "入口菜单 3) 进入 UT紧急回滚并完成" || bad "入口回滚失败: $(tail -3 /tmp/t3.out)"
grep -q 'nix-env --switch-generation 22 -p /tmp/fakeprof' /tmp/stub.log && ok "切换到 generation 22" || bad "未调用 switch-generation 22"
grep -q 'switch-to-configuration switch' /tmp/stub.log && ok "激活 generation" || bad "未调用 switch-to-configuration"

echo ""
echo "========== 测试 4：install.sh repair（一键修复 /etc/nixos） =========="
# /etc/nixos 被搞坏（缺 flake.nix/install.sh → ut/面板失去配置）：
# repair 应保留机器文件、拉取/复用最新代码重建 /etc/nixos 并触发 nixos-rebuild。
rm -f /etc/nixos/flake.nix /etc/nixos/install.sh   # 模拟损坏（单文件时代没有 script/）
echo '# MACHINE hardware' > /etc/nixos/hardware-configuration.nix
printf '# machine packages\nhtop\n' > /etc/nixos/host/packages.nix
grep -q '^DESKTOP=' /etc/nixos/.utnixos-pro-selection 2>/dev/null || echo 'DESKTOP=kde' >> /etc/nixos/.utnixos-pro-selection
INPUT=()   # 重建确认（回车=是）
pty_in "bash /repo/install.sh repair" /tmp/t4.out ''
grep -E "修复 /etc/nixos 配置|修复完成|✓|✗" /tmp/t4.out | head -6
[ -f /etc/nixos/flake.nix ] && ok "repair 恢复 flake.nix" || bad "flake.nix 未恢复"
[ -f /etc/nixos/install.sh ] && ok "repair 恢复 install.sh" || bad "install.sh 未恢复"
[ ! -d /etc/nixos/script ] && ok "repair 后无 script/（单文件化）" || bad "script/ 不应出现"
check "repair 恢复内置 webui 导入" '^[[:space:]]*\./modules/system/webui\.nix' /etc/nixos/configuration.nix
[ "$(cat /etc/nixos/hardware-configuration.nix)" = '# MACHINE hardware' ] \
  && ok "repair 保留 hardware-configuration.nix" || bad "硬件配置丢失"
grep -q 'htop' /etc/nixos/host/packages.nix && ok "repair 保留 host/packages.nix" || bad "packages.nix 丢失"
grep -q '^DESKTOP=kde$' /etc/nixos/.utnixos-pro-selection && ok "repair 保留选择状态" || bad "选择状态丢失"
grep -q 'nixos-rebuild switch --flake /etc/nixos#reimilia' /tmp/stub.log \
  && ok "repair 触发 nixos-rebuild" || bad "repair 未触发重建"
ls -d /etc/nixos.repair-* >/dev/null 2>&1 && ok "repair 生成备份目录" || bad "repair 未备份旧配置"

# stdin 形式：bash -s -- repair（参数可能落在 $0 或 $1，两种都要能进修复）
rm -f /etc/nixos/flake.nix
export UTNIXOS_PRO_GIT_URL="file:///repo"   # stdin 执行时无本地仓库可用 → repair 自己拉取
INPUT=()   # 跳过重建（n），只验证路由与恢复
pty_in "bash -s -- repair < /repo/install.sh" /tmp/t4b.out 'n'
unset UTNIXOS_PRO_GIT_URL
grep -q "修复 /etc/nixos 配置" /tmp/t4b.out && ok "bash -s -- repair（stdin）能进修复" || bad "stdin 形式未进修复: $(tail -3 /tmp/t4b.out)"
[ -f /etc/nixos/flake.nix ] && ok "stdin 修复后 flake.nix 存在" || bad "stdin 修复后 flake.nix 缺失"

echo ""
echo "========== 测试 5：install.sh rollback（UT紧急回滚到指定 generation） =========="
rm -f /tmp/stub.log
INPUT=()   # 回滚到 generation 22
pty_in "bash /etc/nixos/install.sh rollback" /tmp/t5.out '22'
grep -q 'UT紧急回滚' /tmp/t5.out && ok "回滚标题为 UT紧急回滚" || bad "缺少 UT紧急回滚 标题"
grep -q '回滚完成' /tmp/t5.out && ok "回滚完成" || bad "回滚失败: $(tail -3 /tmp/t5.out)"
grep -q 'nix-env --switch-generation 22 -p /tmp/fakeprof' /tmp/stub.log && ok "切换到 generation 22" || bad "未调用 switch-generation 22"
grep -q 'switch-to-configuration switch' /tmp/stub.log && ok "激活 generation" || bad "未调用 switch-to-configuration"
# 空输入分支：回滚到上一个版本
rm -f /tmp/stub.log
INPUT=()   # 回车=回滚到上一个版本
pty_in "bash /etc/nixos/install.sh rollback" /tmp/t5b.out ''
grep -q 'nixos-rebuild switch --rollback' /tmp/stub.log && ok "默认回滚分支调用 nixos-rebuild --rollback" || bad "默认回滚分支未触发"

echo ""
echo "========== 测试 6：自包含引导（单文件即可运行，回滚无需拉取仓库） =========="
mkdir -p /tmp/alone && cp /repo/install.sh /tmp/alone/install.sh
rm -rf /etc/nixos && mkdir -p /etc/nixos
# 把 /etc/nixos 变成非仓库目录（无 flake.nix）：证明回滚不依赖 /etc/nixos 里的配置/仓库
unset UTNIXOS_PRO_GIT_URL
INPUT=()   # 回滚到 generation 23
export UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
pty_in "bash /tmp/alone/install.sh --rollback" /tmp/t6.out '23'
grep -q '回滚完成' /tmp/t6.out && ok "独立单文件 --rollback 可用（未拉取仓库）" || bad "引导回滚失败: $(tail -3 /tmp/t6.out)"
grep -q 'nix-env --switch-generation 23 -p /tmp/fakeprof' /tmp/stub.log && ok "切换到 generation 23" || bad "未调用 switch-generation 23"

# 清理现场
rm -rf /etc/nixos /nix/var/nix/profiles/system /tmp/fakeprof

echo ""
echo "=========================================="
echo "脚本测试结果：PASS=$PASS FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
