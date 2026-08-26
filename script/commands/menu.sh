# UTNixOS_Pro 命令：选择/更换模块（script/commands/menu.sh）
# 只交互选择模块并重建，不拉取代码。

cmd_menu() {
  banner
  [[ $EUID -eq 0 ]] || die "模块管理需要 root，请用：sudo bash install.sh menu"

  TARGET_DIR="$INSTALL_DIR"
  [[ -f "$TARGET_DIR/flake.nix" ]] || die "/etc/nixos 下没有 flake.nix，看起来不是由本脚本安装的系统？"
  cd "$TARGET_DIR"

  load_state
  run_menu
  apply_selection
  show_selection

  prompt "确认修改并重建系统？[y/N] "
  local ans=""
  read -r ans < /dev/tty || ans="n"
  [[ "$ans" =~ ^[Yy]$ ]] || die "已取消，configuration.nix 已修改但未重建（可手动 nixos-rebuild switch）"

  info "开始重建系统..."
  nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
  ok "模块切换完成！"
}
