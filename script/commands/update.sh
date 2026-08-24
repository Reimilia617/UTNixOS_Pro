# UTnixOS 命令：更新配置（script/commands/update.sh）
# 从 GitHub 同步最新代码（保留本机 hardware-configuration.nix 和选择状态），
# 恢复上次的模块选择（或重新选择），然后 nixos-rebuild switch。

cmd_update() {
  banner
  [[ $EUID -eq 0 ]] || die "更新模式需要 root，请用：sudo bash install.sh update"

  TARGET_DIR="$INSTALL_DIR"
  [[ -f "$TARGET_DIR/flake.nix" ]] || die "/etc/nixos 下没有 flake.nix，看起来不是由本脚本安装的系统？"
  cd "$TARGET_DIR"

  load_state

  info "从 GitHub 同步最新代码..."
  if [[ -d "$TARGET_DIR/.git" ]]; then
    git fetch origin >/dev/null 2>&1 || warn "git fetch 失败（网络问题？），将使用本地已有代码"
    git reset --hard origin/main >/dev/null 2>&1 || warn "git reset 失败，继续使用现有代码"
    git update-index --skip-worktree hardware-configuration.nix 2>/dev/null || true
  else
    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$tmp" --strip-components=1 || die "下载最新代码失败"
    # 备份机器专属文件
    cp -f hardware-configuration.nix "$tmp/" 2>/dev/null || true
    cp -f "$STATE_FILE" "$tmp/" 2>/dev/null || true
    # 原子替换（保留一个 .old 以防万一）
    rm -rf /etc/nixos.old
    mv "$TARGET_DIR" /etc/nixos.old
    mkdir -p "$TARGET_DIR"
    cp -r "$tmp/." "$TARGET_DIR/"
    ok "代码已更新（旧配置备份在 /etc/nixos.old，确认没问题后可删除）"
  fi

  # 重新应用上次的选择（configuration.nix 已回到默认状态）
  if [[ -n "${DESKTOP:-}" ]]; then
    apply_selection
  fi

  prompt "是否要重新选择模块？（比如换桌面环境）[y/N] "
  local ans=""
  read -r ans < /dev/tty || ans="n"
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    run_menu
    apply_selection
  fi

  show_selection
  info "开始重建系统（nixos-rebuild switch）..."
  nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
  ok "系统更新完成！"
}
