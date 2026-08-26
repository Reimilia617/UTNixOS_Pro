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
#   2. install.sh install  自定义选项（gnome/systemd-boot/zh_CN/fcitx5/tuna/fish/webui/secrets）
#   3. install.sh menu     已装系统换模块（kde + 重建）
#   4. install.sh update   同步代码 + 保留机器文件 + 重放选择 + 重建
#   5. install.sh rollback 回滚到指定 generation（stub profile）
#   6. install.sh 引导模式（curl|bash 等价路径：从 GIT_URL 拉取模块）
# ============================================================================
set -u
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
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
INPUT=$(printf '\n\n\n\n\n\n\n\n\ny\n')
echo "$INPUT" | script -qec "bash /repo/install.sh install" /dev/null >/tmp/t1.out 2>&1
echo "--- 输出片段 ---"; grep -E "安装完成|✓|✗|错误" /tmp/t1.out | head -8
CFG=/mnt/etc/nixos/configuration.nix
[ -f "$CFG" ] && ok "configuration.nix 已部署到 /mnt/etc/nixos" || bad "configuration.nix 未部署"
[ -f /mnt/etc/nixos/.utnixos-pro-selection ] && ok ".utnixos-pro-selection 已生成" || bad ".utnixos-pro-selection 未生成"
[ -f /mnt/etc/nixos/hardware-configuration.nix ] && ok "hardware-configuration.nix 已生成" || bad "hardware-configuration.nix 未生成"
[ -f /mnt/etc/nixos/script/main.sh ] && ok "script/ 模块已随配置部署" || bad "script/ 未部署"
check "桌面默认 xfce 启用"        '^[[:space:]]*\./modules/desktop/xfce\.nix' "$CFG"
check_not "桌面 gnome 未启用"     '^[[:space:]]*[^#]*\./modules/desktop/gnome\.nix' "$CFG"
check "引导默认 GRUB+主题"        '^[[:space:]]*\./modules/boot/grub\.nix' "$CFG"
check "语言默认 en_US"            '^[[:space:]]*\./modules/locale/en_US\.nix' "$CFG"
check "输入法默认 ibus"           '^[[:space:]]*\./modules/input/ibus\.nix' "$CFG"
check "镜像默认 ustc"             '^[[:space:]]*\./modules/mirrors/ustc\.nix' "$CFG"
check "Shell 默认 zsh"            '^[[:space:]]*\./modules/shell/zsh\.nix' "$CFG"
for m in auto-update clean nix-command zram fonts; do
  check "系统模块 $m 默认启用"    "^[[:space:]]*\./modules/system/$m\.nix" "$CFG"
done
check_not "webui 默认关闭"        '^[[:space:]]*[^#]*\./modules/system/webui\.nix' "$CFG"
check_not "secrets 默认关闭"      '^[[:space:]]*[^#]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=zsh"    '^[[:space:]]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=xfce$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=xfce" || bad "状态文件 DESKTOP 错误"
grep -q '^USERSHELL=zsh$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=zsh" || bad "状态文件 USERSHELL 错误"
grep -q 'nixos-install --flake /mnt/etc/nixos#reimilia --option substituters' /tmp/stub.log \
  && ok "nixos-install 以 flake+镜像源 调用" || bad "nixos-install 调用参数不符: $(grep nixos-install /tmp/stub.log)"

echo ""
echo "========== 测试 2：install.sh install（自定义选项） =========="
# gnome(2) systemd-boot(3) zh_CN(2) fcitx5(2) tuna(2) fish(3) webui(8) secrets(1)
INPUT=$(printf '2\n3\n2\n2\n2\n3\n8\n\n1\n\ny\n')
echo "$INPUT" | script -qec "bash /repo/install.sh install" /dev/null >/tmp/t2.out 2>&1
grep -E "安装完成|✓|✗" /tmp/t2.out | head -6
check "自定义桌面 gnome 启用"     '^[[:space:]]*\./modules/desktop/gnome\.nix' "$CFG"
check_not "xfce 被注释"           '^[[:space:]]*[^#]*\./modules/desktop/xfce\.nix' "$CFG"
check "systemd-boot 启用"         '^[[:space:]]*\./modules/boot/systemd-boot\.nix' "$CFG"
check_not "grub 被注释"           '^[[:space:]]*[^#]*\./modules/boot/grub\.nix' "$CFG"
check "zh_CN 启用"                '^[[:space:]]*\./modules/locale/zh_CN\.nix' "$CFG"
check "fcitx5 启用"               '^[[:space:]]*\./modules/input/fcitx5\.nix' "$CFG"
check "tuna 启用"                 '^[[:space:]]*\./modules/mirrors/tuna\.nix' "$CFG"
check "fish 启用"                 '^[[:space:]]*\./modules/shell/fish\.nix' "$CFG"
check "webui 启用"                '^[[:space:]]*\./modules/system/webui\.nix' "$CFG"
check "secrets 启用"              '^[[:space:]]*\./modules/system/secrets\.nix' "$CFG"
check "home-manager shell=fish"   '^[[:space:]]*\./shell/fish\.nix' /mnt/etc/nixos/home/home-manager.nix
check_not "home-manager zsh 关闭" '^[[:space:]]*[^#]*\./shell/zsh\.nix' /mnt/etc/nixos/home/home-manager.nix
grep -q '^DESKTOP=gnome$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 DESKTOP=gnome" || bad "状态文件 DESKTOP 错误"
grep -q '^BOOT=systemd-boot$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 BOOT=systemd-boot" || bad "状态文件 BOOT 错误"
grep -q '^USERSHELL=fish$' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 USERSHELL=fish" || bad "状态文件 USERSHELL 错误"
grep -q '^SYSTEM_MODULES=.*webui' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 含 webui" || bad "状态文件 不含 webui"
grep -q '^ADVANCED=secrets' /mnt/etc/nixos/.utnixos-pro-selection && ok "状态文件 含 secrets" || bad "状态文件 不含 secrets"

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
# kde(3) 其余默认
INPUT=$(printf '3\n\n\n\n\n\n\n\n\ny\n')
echo "$INPUT" | script -qec "bash /etc/nixos/install.sh menu" /dev/null >/tmp/t3.out 2>&1
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
INPUT=$(printf 'n\n')   # 不重新选择模块
echo "$INPUT" | script -qec "bash /etc/nixos/install.sh update" /dev/null >/tmp/t4.out 2>&1
grep -E "系统更新完成|✓|✗" /tmp/t4.out | head -5
[ "$(cat /etc/nixos/hardware-configuration.nix)" = "$BEFORE_HW" ] && ok "hardware-configuration.nix 被保留" || bad "hardware-configuration.nix 丢失/被覆盖"
[ "$(cat /etc/nixos/host/packages.nix)" = "$BEFORE_PKG" ] && ok "host/packages.nix 被保留" || bad "host/packages.nix 丢失/被覆盖"
[ -f /etc/nixos/.utnixos-pro-selection ] && ok "选择状态文件被保留" || bad "选择状态文件丢失"
check "update 后重放选择 kde"    '^[[:space:]]*\./modules/desktop/kde\.nix' /etc/nixos/configuration.nix
N=$(grep -c 'nixos-rebuild switch --flake /etc/nixos#reimilia' /tmp/stub.log)
[ "$N" -ge 2 ] && ok "update 触发了 nixos-rebuild（共 $N 次）" || bad "update 未触发 nixos-rebuild"

echo ""
echo "========== 测试 5：install.sh rollback（回滚到指定 generation） =========="
mkdir -p /tmp/fakeprof
export UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof
INPUT=$(printf '22\n')
echo "$INPUT" | script -qec "bash /etc/nixos/install.sh rollback" /dev/null >/tmp/t5.out 2>&1
grep -E "回滚完成|✓|✗" /tmp/t5.out | head -3
grep -q 'nix-env --switch-generation 22 -p /tmp/fakeprof' /tmp/stub.log && ok "切换到 generation 22" || bad "未调用 switch-generation 22"
grep -q 'switch-to-configuration switch' /tmp/stub.log && ok "激活 generation" || bad "未调用 switch-to-configuration"
# 空输入分支：回滚到上一个版本
INPUT=$(printf '\n')
echo "$INPUT" | script -qec "bash /etc/nixos/install.sh rollback" /dev/null >/tmp/t5b.out 2>&1
grep -q 'nixos-rebuild switch --rollback' /tmp/stub.log && ok "默认回滚分支调用 nixos-rebuild --rollback" || bad "默认回滚分支未触发"

echo ""
echo "========== 测试 6：引导模式（curl|bash 等价：从 GIT_URL 拉取模块） =========="
mkdir -p /tmp/alone && cp /repo/install.sh /tmp/alone/install.sh
# help 模式：只验证拉取+路由
UTNIXOS_PRO_GIT_URL=file:///repo bash /tmp/alone/install.sh help >/tmp/t6.out 2>&1
grep -q "正在从 GitHub 获取 UTNixOS_Pro 脚本" /tmp/t6.out && ok "引导模式从 GIT_URL 拉取代码" || bad "引导模式未拉取"
grep -q "curl 方式安装" /tmp/t6.out && ok "help 路由正常" || bad "help 输出异常"
# --rollback 走引导模式完整回滚（保险方案路径）
INPUT=$(printf '22\n')
echo "$INPUT" | UTNIXOS_PRO_GIT_URL=file:///repo UTNIXOS_PRO_TEST_PROF=/tmp/fakeprof \
  script -qec "bash /tmp/alone/install.sh --rollback" /dev/null >/tmp/t6b.out 2>&1
grep -q '回滚完成' /tmp/t6b.out && ok "curl|bash --rollback 保险回滚可用" || bad "引导回滚失败: $(tail -3 /tmp/t6b.out)"

echo ""
echo "=========================================="
echo "脚本测试结果：PASS=$PASS FAIL=$FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
