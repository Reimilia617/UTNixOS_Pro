# UTnixOS 命令：管理面板（script/commands/dashboard.sh）
# ut 命令 / install.sh 无参数时的默认入口。
# 提供：重建系统 / 清理垃圾 / 更换模块 / 更新配置 / 更新Flake / 回滚。

cmd_dashboard() {
  banner
  [[ $EUID -eq 0 || -n "${UTNIXOS_TEST:-}" ]] || die "管理面板需要 root，请用：sudo install.sh 或直接运行 ut"

  TARGET_DIR="$INSTALL_DIR"
  if [[ ! -f "$TARGET_DIR/flake.nix" ]]; then
    warn "/etc/nixos 下没有 flake.nix，面板的重建/更新功能不可用"
    warn "（回滚功能不依赖配置，可继续使用）"
  fi

  while :; do
    say ""
    say "${C_BOLD}========== UTNixOS 管理菜单 ==========${C_RESET}"
    say "  1) 重建系统（nixos-rebuild switch）"
    say "  2) 清理构建垃圾（nix-collect-garbage -d）"
    say "  3) 选择/更换模块（桌面/引导/Shell/输入法等）"
    say "  4) 更新配置（从 GitHub 同步最新代码 + 重建）"
    say "  5) 更新 Flake（nix flake update 所有输入 + 重建）"
    say "  6) 系统回滚（选择之前的 generation）"
    say "  7) 退出"
    prompt "请选择 [1-7]: "
    local choice=""
    read -r choice < /dev/tty || choice="7"
    case "$choice" in
      1)
        info "开始重建系统..."
        nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
        ok "重建完成！"
        ;;
      2)
        info "清理构建垃圾（保留最近7天的历史）..."
        nix-collect-garbage -d
        ok "清理完成！"
        ;;
      3)
        cmd_menu
        ;;
      4)
        cmd_update
        ;;
      5)
        info "更新 flake.lock（nix flake update）..."
        (cd "$TARGET_DIR" && nix flake update)
        info "开始重建系统..."
        nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
        ok "Flake 更新并重建完成！"
        ;;
      6)
        cmd_rollback
        ;;
      7)
        say "再见！"
        return 0
        ;;
      *) warn "无效选择：$choice" ;;
    esac
  done
}
