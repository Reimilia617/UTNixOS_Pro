# UTNixOS_Pro 命令：管理面板（script/commands/dashboard.sh）
# ut 命令 / install.sh 无参数时的默认入口。
# 提供：重建系统 / 清理垃圾 / 更换模块 / 更新配置 / 更新Flake / 回滚 / 一键修复。

cmd_dashboard() {
  banner
  [[ $EUID -eq 0 || -n "${UTNIXOS_PRO_TEST:-}" ]] || die dash_root

  TARGET_DIR="$INSTALL_DIR"
  if [[ ! -f "$TARGET_DIR/flake.nix" ]]; then
    warn dash_noflake
    warn dash_noflake2
  fi

  while :; do
    say ""
    say "${C_BOLD}$(_t dash_title)${C_RESET}"
    say dash_opt1
    say dash_opt2
    say dash_opt3
    say dash_opt4
    say dash_opt5
    say dash_opt6
    say dash_opt7
    say dash_opt8
    prompt dash_choose
    local choice=""
    read -r choice < /dev/tty || choice="8"
    # 彩蛋：输入 touhou 播放 Bad Apple!!（与模块选择菜单一致）
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    case "$choice" in
      1)
        info rebuild_doing
        nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
        ok rebuild_done
        ;;
      2)
        info dash_gc
        nix-collect-garbage -d
        ok dash_gc_done
        ;;
      3)
        cmd_menu
        ;;
      4)
        cmd_update
        ;;
      5)
        info dash_flake_update
        (cd "$TARGET_DIR" && nix flake update)
        info rebuild_doing
        nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
        ok dash_flake_done
        ;;
      6)
        cmd_rollback
        ;;
      7)
        cmd_repair
        ;;
      8)
        say dash_bye
        return 0
        ;;
      *) warn dash_invalid "$choice" ;;
    esac
  done
}
