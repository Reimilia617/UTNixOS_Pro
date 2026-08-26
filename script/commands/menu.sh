# UTNixOS_Pro 命令：选择/更换模块（script/commands/menu.sh）
# 只交互选择模块并重建，不拉取代码。

cmd_menu() {
  banner
  [[ $EUID -eq 0 ]] || die menu_root

  TARGET_DIR="$INSTALL_DIR"
  [[ -f "$TARGET_DIR/flake.nix" ]] || die noflake
  cd "$TARGET_DIR"

  load_state
  run_menu
  apply_selection
  show_selection

  prompt menu_confirm
  local ans=""
  read -r ans < /dev/tty || ans="n"
  [[ "$ans" =~ ^[Yy]$ ]] || die menu_cancel

  info rebuild_doing
  nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
  ok menu_done
}
