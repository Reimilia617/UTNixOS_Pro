# UTnixOS 命令：系统回滚（script/commands/rollback.sh）
# 纯操作系统 profile 的 generations，不依赖 /etc/nixos 配置——
# 所以即使本地配置/脚本坏了，也可以用 curl 拉最新脚本加 --rollback 回滚。

cmd_rollback() {
  banner
  # 允许测试时用 UTNIXOS_TEST_PROF 覆盖 profile 路径
  local PROF="${UTNIXOS_TEST_PROF:-/nix/var/nix/profiles/system}"
  [[ -e "$PROF" ]] || die "找不到系统 profile：$PROF"

  say ""
  say "${C_BOLD}当前系统 generations：${C_RESET}"
  nix-env --list-generations -p "$PROF" 2>/dev/null || nix profile history --profile "$PROF" 2>/dev/null || die "无法读取 generations"
  say ""
  say "当前运行 : $(readlink -f /run/current-system 2>/dev/null || echo 未知)"

  prompt "输入要回滚到的 generation 编号（直接回车 = 回滚到上一个版本）: "
  local gen=""
  read -r gen < /dev/tty || gen=""

  if [[ -z "$gen" ]]; then
    info "执行 nixos-rebuild switch --rollback（回滚到上一个版本）..."
    nixos-rebuild switch --rollback
  else
    info "切换系统 profile 到 generation $gen ..."
    nix-env --switch-generation "$gen" -p "$PROF"
    info "激活该 generation ..."
    /run/current-system/bin/switch-to-configuration switch
  fi

  ok "回滚完成！如果引导还有问题，重启时可以在 GRUB 菜单里选择其他 generation"
}
