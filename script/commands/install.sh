# UTNixOS 命令：全新安装（script/commands/install.sh）
# 在 NixOS live 环境运行：已挂载 /mnt，自动生成硬件配置、部署文件、执行 nixos-install。

cmd_install() {
  banner
  [[ $EUID -eq 0 || -n "${UTNIXOS_TEST:-}" ]] || die "安装模式需要 root 权限（NixOS live 环境默认就是 root）"

  TARGET_DIR="$MOUNT_ROOT/etc/nixos"

  say ""
  info "检查挂载情况..."
  mountpoint -q "$MOUNT_ROOT" || die "系统分区似乎没有挂载到 $MOUNT_ROOT\n请先执行：mount /dev/你的根分区 $MOUNT_ROOT"
  if mountpoint -q "$MOUNT_ROOT/boot/efi" || mountpoint -q "$MOUNT_ROOT/boot"; then
    ok "检测到引导分区已挂载"
  else
    warn "没检测到 $MOUNT_ROOT/boot 或 $MOUNT_ROOT/boot/efi（BIOS/MBR 方式可忽略）"
  fi
  command -v nixos-install >/dev/null || die "没找到 nixos-install，请确认你在 NixOS live 环境里"
  command -v nixos-generate-config >/dev/null || die "没找到 nixos-generate-config"

  # 交互选择
  if [[ -z "${DESKTOP:-}" ]]; then
    run_menu
  fi
  show_selection

  prompt "确认以上选择并开始安装？[y/N] "
  local ans=""
  read -r ans < /dev/tty || ans="n"
  [[ "$ans" =~ ^[Yy]$ ]] || die "已取消"

  # 获取配置源码：优先复用引导时拉取的仓库（SCRIPT_SRC，带 .git），否则自己拉取
  info "准备 UTNixOS 配置..."
  local src=""
  if [[ -d "${SCRIPT_SRC:-}/.git" ]]; then
    src="$SCRIPT_SRC"
    ok "复用已拉取的代码：$src"
  else
    src="$(mktemp -d)"
    if command -v git >/dev/null 2>&1; then
      clone_config "$src" || die "git clone 失败，请检查网络"
    else
      curl -fsSL "$TARBALL_URL" | tar -xz -C "$src" --strip-components=1 || die "下载失败"
      # tarball 方式下 --no-apple：直接删掉 mp4
      [[ "${NO_APPLE:-0}" == "1" ]] && rm -f "$src/media/badapple.mp4"
    fi
  fi

  info "生成这台机器的 hardware-configuration.nix ..."
  nixos-generate-config --root "$MOUNT_ROOT"

  info "部署配置文件到 $TARGET_DIR ..."
  mkdir -p "$TARGET_DIR"
  # 复制全部文件（保留 .git 以便以后 update），但不覆盖刚生成的 hardware-configuration.nix
  # --no-apple 时排除 badapple.mp4（引导/克隆阶段已跳过下载，这里兜底排除）
  local rsync_opts=(-a --exclude='hardware-configuration.nix')
  [[ "${NO_APPLE:-0}" == "1" ]] && rsync_opts+=(--exclude='media/badapple.mp4')
  rsync "${rsync_opts[@]}" "$src/" "$TARGET_DIR/"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    git -C "$TARGET_DIR" update-index --skip-worktree hardware-configuration.nix 2>/dev/null || true
  fi

  # 应用选择
  apply_selection

  say ""
  info "开始安装系统（下载可能需要较长时间，请耐心等待）..."
  nixos-install --flake "$TARGET_DIR#reimilia" \
    --option substituters "${MIRROR_URLS[$MIRROR]:-${MIRROR_URLS[ustc]}}"

  say ""
  ok "${C_BOLD}安装完成！${C_RESET}"
  say "  1. 输入 reboot 重启"
  say "  2. 用 reimilia / 123456 登录，然后立即执行 passwd 修改密码"
  say "  3. 以后管理系统：ut（或 sudo bash /etc/nixos/install.sh）"
}
