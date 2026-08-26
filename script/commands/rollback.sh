# UTNixOS_Pro 命令：系统回滚（script/commands/rollback.sh）
# 纯操作系统 profile 的 generations，不依赖 /etc/nixos 配置——
# 所以即使本地配置/脚本坏了，也可以用 curl 拉最新脚本加 --rollback 回滚。

cmd_rollback() {
  banner
  # 允许测试时用 UTNIXOS_PRO_TEST_PROF 覆盖 profile 路径
  local PROF="${UTNIXOS_PRO_TEST_PROF:-/nix/var/nix/profiles/system}"
  [[ -e "$PROF" ]] || die roll_no_profile "$PROF"

  say ""
  say "${C_BOLD}$(_t roll_current_gen)${C_RESET}"
  nix-env --list-generations -p "$PROF" 2>/dev/null || nix profile history --profile "$PROF" 2>/dev/null || die roll_no_read
  say ""
  say roll_current_run "$(readlink -f /run/current-system 2>/dev/null || echo $(_t roll_unknown))"

  prompt roll_prompt
  local gen=""
  read -r gen < /dev/tty || gen=""

  if [[ -z "$gen" ]]; then
    info roll_exec
    nixos-rebuild switch --rollback
  else
    info roll_switch_gen "$gen"
    nix-env --switch-generation "$gen" -p "$PROF"
    info roll_activate
    /run/current-system/bin/switch-to-configuration switch
  fi

  ok roll_done
}
