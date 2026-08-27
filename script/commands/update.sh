# UTNixOS_Pro 命令：更新配置（script/commands/update.sh）
# 从 GitHub 同步最新代码（保留本机 hardware-configuration.nix 和选择状态），
# 恢复上次的模块选择（或重新选择），然后 nixos-rebuild switch。

cmd_update() {
  banner
  [[ $EUID -eq 0 ]] || die upd_root

  TARGET_DIR="$INSTALL_DIR"
  [[ -f "$TARGET_DIR/flake.nix" ]] || die noflake
  cd "$TARGET_DIR"

  load_state

  info upd_sync
  if [[ -d "$TARGET_DIR/.git" ]]; then
    # 备份机器本地文件（Web 面板的软件包 / GRUB BIOS 设备 / 硬件配置），更新后恢复，防止被 reset 覆盖
    local bk
    bk=$(mktemp -d)
    cp -f hardware-configuration.nix "$bk/" 2>/dev/null || true
    cp -f host/packages.nix "$bk/" 2>/dev/null || true
    cp -f host/grub-device.nix "$bk/" 2>/dev/null || true
    git fetch origin >/dev/null 2>&1 || warn upd_fetch_fail
    git reset --hard origin/main >/dev/null 2>&1 || warn upd_reset_fail
    # 恢复机器本地文件（注意备份时是 $bk/packages.nix，不是 $bk/host/）
    mkdir -p "$TARGET_DIR/host"
    cp -f "$bk/hardware-configuration.nix" "$TARGET_DIR/" 2>/dev/null || true
    cp -f "$bk/packages.nix" "$TARGET_DIR/host/" 2>/dev/null || true
    cp -f "$bk/grub-device.nix" "$TARGET_DIR/host/" 2>/dev/null || true
    rm -rf "$bk"
    git update-index --skip-worktree hardware-configuration.nix 2>/dev/null || true
    git update-index --skip-worktree host/packages.nix 2>/dev/null || true
    git update-index --skip-worktree host/grub-device.nix 2>/dev/null || true
  else
    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$tmp" --strip-components=1 || die upd_dl_fail
    # 备份机器专属文件
    cp -f hardware-configuration.nix "$tmp/" 2>/dev/null || true
    cp -f "$STATE_FILE" "$tmp/" 2>/dev/null || true
    mkdir -p "$tmp/host"
    cp -f host/packages.nix "$tmp/host/" 2>/dev/null || true
    cp -f host/grub-device.nix "$tmp/host/" 2>/dev/null || true
    # 原子替换（保留一个 .old 以防万一；路径跟随 TARGET_DIR，便于测试/多目录）
    local old_dir="${TARGET_DIR}.old"
    rm -rf "$old_dir"
    mv "$TARGET_DIR" "$old_dir"
    mkdir -p "$TARGET_DIR"
    cp -r "$tmp/." "$TARGET_DIR/"
    ok upd_code_ok "$old_dir"
  fi

  # 重新应用上次的选择（configuration.nix 已回到默认状态）
  if [[ -n "${DESKTOP:-}" ]]; then
    apply_selection
  fi

  prompt upd_rechoose
  local ans=""
  read -r ans < /dev/tty || ans="n"
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    run_menu
    apply_selection
  fi

  show_selection
  info upd_rebuild
  nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
  ok upd_done
}
