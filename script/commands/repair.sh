# UTNixOS_Pro 命令：一键修复（script/commands/repair.sh）
#
# 场景：/etc/nixos 被搞坏（缺 flake.nix / install.sh / script/，ut 崩、面板报 noflake）
# 时，一键拉取最新代码重建 /etc/nixos，并保留机器专属文件：
#   - hardware-configuration.nix（硬件配置）
#   - host/packages.nix（Web 面板安装的软件包）
#   - host/grub-device.nix（GRUB BIOS 目标磁盘）
#   - .utnixos-pro-selection（模块选择状态，会重新应用到 configuration.nix）
#
# 运行方式（都可）：
#   sudo bash /etc/nixos/install.sh repair     # /etc/nixos 还能用时
#   curl -L <install.sh> | sudo bash -s -- repair   # /etc/nixos 坏了也能修
#   ut repair
#
# 安全设计：先全量备份 /etc/nixos 到 /etc/nixos.repair-<时间戳>；拉取失败/复制失败
# 绝不删除旧配置，失败自动回滚。

cmd_repair() {
  banner
  [[ $EUID -eq 0 ]] || die repair_root

  TARGET_DIR="$INSTALL_DIR"

  info repair_start

  # ---------- 1. 全量备份现有 /etc/nixos（绝不先删） ----------
  local bk="${TARGET_DIR}.repair-$(date +%Y%m%d-%H%M%S)"
  local have_bk=0
  if [[ -d "$TARGET_DIR" ]]; then
    cp -a "$TARGET_DIR" "$bk" 2>/dev/null && { have_bk=1; ok repair_backup "$bk"; }
  fi

  # ---------- 2. 收集机器专属文件（备份目录优先，其次失败的更新留下的 .old） ----------
  local mf
  mf="$(mktemp -d)"
  local mdir
  for mdir in "$bk" "${TARGET_DIR}.old"; do
    [[ -d "$mdir" ]] || continue
    [[ -f "$mf/hardware-configuration.nix" ]] || cp -f "$mdir/hardware-configuration.nix" "$mf/" 2>/dev/null || true
    [[ -f "$mf/packages.nix" ]]            || cp -f "$mdir/host/packages.nix" "$mf/" 2>/dev/null || true
    [[ -f "$mf/grub-device.nix" ]]         || cp -f "$mdir/host/grub-device.nix" "$mf/" 2>/dev/null || true
    [[ -f "$mf/.utnixos-pro-selection" ]]  || cp -f "$mdir/.utnixos-pro-selection" "$mf/" 2>/dev/null || true
  done

  # ---------- 3. 获取最新源码：优先复用引导器拉取的临时代码，否则从 GitHub 拉取 ----------
  # 注意：SCRIPT_SRC 若等于 TARGET_DIR（即从 /etc/nixos/install.sh 直接跑 repair），
  # 说明「本地配置」被当成源码——它可能是旧代码，绝不能复用，必须拉最新的。
  local src=""
  if [[ "${SCRIPT_SRC:-}" != "$TARGET_DIR" \
        && -f "${SCRIPT_SRC:-}/flake.nix" && -f "${SCRIPT_SRC:-}/install.sh" && -f "${SCRIPT_SRC:-}/script/main.sh" ]]; then
    src="$SCRIPT_SRC"
    ok repair_reuse "$src"
  else
    if [[ "${SCRIPT_SRC:-}" == "$TARGET_DIR" ]]; then
      warn repair_local_stale
    fi
    src="$(mktemp -d)"
    info repair_fetch
    if command -v git >/dev/null 2>&1; then
      clone_config "$src" || true
    fi
    if [[ ! -f "$src/flake.nix" ]] && command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 15 --max-time 600 "$TARBALL_URL" | tar -xz -C "$src" --strip-components=1 || true
    fi
    # 完整性校验：拉取不完整就中止，绝不碰现有配置
    if [[ ! -f "$src/flake.nix" || ! -f "$src/install.sh" || ! -f "$src/script/main.sh" ]]; then
      die repair_fetch_fail
    fi
  fi

  # ---------- 4. 重建 /etc/nixos：完整源码 + 恢复机器文件（失败自动回滚） ----------
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  if ! cp -a "$src/." "$TARGET_DIR/"; then
    # 复制失败 → 从备份回滚
    rm -rf "$TARGET_DIR"
    [[ "$have_bk" == "1" ]] && cp -a "$bk" "$TARGET_DIR" 2>/dev/null
    die repair_swap_fail
  fi
  # 可执行位保险：某些部署方式会丢 mode，install.sh 不可执行会让 sudo 直呼失败
  chmod +x "$TARGET_DIR/install.sh" 2>/dev/null || true
  mkdir -p "$TARGET_DIR/host"
  cp -f "$mf/hardware-configuration.nix" "$TARGET_DIR/" 2>/dev/null || true
  cp -f "$mf/packages.nix" "$TARGET_DIR/host/" 2>/dev/null || true
  cp -f "$mf/grub-device.nix" "$TARGET_DIR/host/" 2>/dev/null || true
  cp -f "$mf/.utnixos-pro-selection" "$TARGET_DIR/" 2>/dev/null || true
  rm -rf "$mf"

  # ---------- 5. 硬件配置缺失时兜底生成（基于当前运行的系统） ----------
  if [[ ! -f "$TARGET_DIR/hardware-configuration.nix" ]]; then
    warn repair_no_hw
    if command -v nixos-generate-config >/dev/null 2>&1; then
      nixos-generate-config || warn repair_no_hw_fail
    fi
  fi

  # ---------- 6. 重放模块选择（有状态文件时） ----------
  if [[ -f "$TARGET_DIR/$STATE_FILE" ]]; then
    load_state
    apply_selection
  fi

  show_selection
  ok repair_ready

  # ---------- 7. 询问是否重建系统（回车=重建，真正的一键） ----------
  prompt repair_confirm
  local ans=""
  read -r ans < /dev/tty || ans="y"
  if [[ "$ans" =~ ^[Nn]$ ]]; then
    say repair_skip
    return 0
  fi
  info rebuild_doing
  nixos-rebuild switch --flake "$TARGET_DIR#reimilia"
  ok repair_done
  # 诚实验证（不猜测）：webui 启用时主动查服务真实状态
  if grep -q '^[[:space:]]*\./modules/system/webui\.nix' "$TARGET_DIR/configuration.nix" \
     && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active utnixos-pro-webui >/dev/null 2>&1; then
      ok repair_webui_active
    else
      warn repair_webui_inactive
    fi
  fi
}
