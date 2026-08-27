# UTNixOS_Pro 命令：全新安装（script/commands/install.sh）
# 在 NixOS live 环境运行：已挂载 /mnt，自动生成硬件配置、部署文件、执行 nixos-install。

cmd_install() {
  banner
  [[ $EUID -eq 0 || -n "${UTNIXOS_PRO_TEST:-}" ]] || die inst_root

  TARGET_DIR="$MOUNT_ROOT/etc/nixos"

  say ""
  info inst_check_mount
  mountpoint -q "$MOUNT_ROOT" || die inst_mount_missing "$MOUNT_ROOT" "$MOUNT_ROOT"
  # NixOS 默认 GRUB/systemd-boot 的 EFI 目录是 /boot（efiSysMountPoint 默认值）；
  # 挂到 /boot/efi（Ubuntu 习惯）会导致引导程序找不到 ESP，这里单独给出警告
  if mountpoint -q "$MOUNT_ROOT/boot"; then
    ok inst_boot_mounted
  elif mountpoint -q "$MOUNT_ROOT/boot/efi"; then
    warn inst_boot_efi_misplaced "$MOUNT_ROOT" "$MOUNT_ROOT"
  else
    warn inst_boot_warn "$MOUNT_ROOT" "$MOUNT_ROOT"
  fi
  command -v nixos-install >/dev/null || die inst_no_nixos_install
  command -v nixos-generate-config >/dev/null || die inst_no_gen_cfg

  # 交互选择
  if [[ -z "${DESKTOP:-}" ]]; then
    run_menu
  fi
  show_selection

  prompt inst_confirm
  local ans=""
  read -r ans < /dev/tty || ans="n"
  [[ "$ans" =~ ^[Yy]$ ]] || die inst_cancel

  # 获取配置源码：优先复用引导时拉取的仓库（SCRIPT_SRC，带 .git），否则自己拉取
  info inst_prep
  local src=""
  if [[ -d "${SCRIPT_SRC:-}/.git" ]]; then
    src="$SCRIPT_SRC"
    ok inst_reuse "$src"
  else
    src="$(mktemp -d)"
    if command -v git >/dev/null 2>&1; then
      clone_config "$src" || die inst_clone_fail
    else
      curl -fsSL "$TARBALL_URL" | tar -xz -C "$src" --strip-components=1 || die inst_dl_fail
      # tarball 方式下 --no-apple：直接删掉 mp4
      [[ "${NO_APPLE:-0}" == "1" ]] && rm -f "$src/media/badapple.mp4"
    fi
  fi

  info inst_gen_hw
  nixos-generate-config --root "$MOUNT_ROOT"

  info inst_deploy "$TARGET_DIR"
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
  info inst_start
  nixos-install --flake "$TARGET_DIR#reimilia" \
    --option substituters "${MIRROR_URLS[$MIRROR]:-${MIRROR_URLS[ustc]}}"

  say ""
  ok "${C_BOLD}$(_t inst_done)${C_RESET}"
  say inst_step1
  say inst_step2
  say inst_step3
}
