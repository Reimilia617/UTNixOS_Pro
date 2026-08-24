# UTNixOS 模块选择逻辑（script/lib/selection.sh）
# 根据菜单选择修改 configuration.nix / home-manager.nix 的 imports，
# 并把选择保存到 .utnixos-selection 以便下次恢复。

# 依赖：env.sh（STATE_FILE 等）、util.sh（info/ok/sed 辅助）

# ---------- 根据选择修改配置文件 ----------
apply_selection() {
  local CFG="$TARGET_DIR/configuration.nix"
  [[ -f "$CFG" ]] || die "找不到 $CFG"
  info "正在把选择写入 $CFG ..."

  # 桌面环境（单选）
  comment_import "$CFG" "desktop/"
  uncomment_import "$CFG" "desktop/${DESKTOP}.nix"

  # 引导（单选：grub-theme / grub-notheme / systemd-boot）
  comment_import "$CFG" "boot/"
  case "$BOOT" in
    systemd-boot) uncomment_import "$CFG" "boot/systemd-boot.nix" ;;
    grub-notheme) uncomment_import "$CFG" "boot/grub.nix" ;;
    *) uncomment_import "$CFG" "boot/grub.nix"; uncomment_import "$CFG" "boot/grub-theme.nix" ;;
  esac

  # 语言环境（单选）
  comment_import "$CFG" "locale/"
  uncomment_import "$CFG" "locale/${LOCALE}.nix"

  # 输入法（单选）
  comment_import "$CFG" "input/"
  uncomment_import "$CFG" "input/${INPUT}.nix"

  # 镜像源（单选）
  comment_import "$CFG" "mirrors/"
  uncomment_import "$CFG" "mirrors/${MIRROR}.nix"

  # 默认 Shell（单选：zsh / bash / fish）
  comment_import "$CFG" "shell/"
  uncomment_import "$CFG" "shell/${USERSHELL}.nix"

  # 同步修改 home-manager 里的 shell 配置导入
  local HM="$TARGET_DIR/home/home-manager.nix"
  if [[ -f "$HM" ]]; then
    sed -i -E "s|^([[:space:]]*)#?(\./shell/[^#]*)|\1#\2|" "$HM"
    sed -i -E "s|^([[:space:]]*)#(\./shell/${USERSHELL}\.nix[^#]*)|\1\2|" "$HM"
  fi

  # 系统模块（多选）
  local m
  for m in auto-update clean nix-command zram fonts nopwdtodesktop vm-debug; do
    if [[ " $SYSTEM_MODULES " == *" $m "* ]]; then
      uncomment_import "$CFG" "system/${m}.nix"
    else
      comment_import "$CFG" "system/${m}.nix"
    fi
  done

  # 进阶模块（多选）
  for m in secrets impermanence backup security; do
    if [[ " $ADVANCED " == *" $m "* ]]; then
      uncomment_import "$CFG" "system/${m}.nix"
    else
      comment_import "$CFG" "system/${m}.nix"
    fi
  done

  # 保存选择状态
  save_state
  ok "configuration.nix 已更新"
}

# ---------- 选择状态持久化 ----------
save_state() {
  local st="$TARGET_DIR/$STATE_FILE"
  cat > "$st" <<EOF
# UTNixOS 模块选择状态（由 install.sh 生成，可手动修改后重新运行 update）
DESKTOP=$DESKTOP
BOOT=$BOOT
LOCALE=$LOCALE
INPUT=$INPUT
MIRROR=$MIRROR
USERSHELL=$USERSHELL
SYSTEM_MODULES=$SYSTEM_MODULES
ADVANCED=$ADVANCED
EOF
}

load_state() {
  local st="$TARGET_DIR/$STATE_FILE"
  if [[ -f "$st" ]]; then
    # shellcheck disable=SC1090
    . "$st"
    ok "已恢复上次的模块选择"
  fi
}

# ---------- 交互式选择全部模块 ----------
run_menu() {
  say ""
  say "${C_BOLD}请选择要启用的模块（同类只能选一个，避免冲突）${C_RESET}"
  say "${C_YELLOW}提示：直接回车使用默认值/第1项${C_RESET}"

  pick_one "桌面环境（默认 xfce）" xfce gnome kde lxqt hyprland cosmic
  DESKTOP="$PICKED"

  pick_one "引导加载器（默认 GRUB+东方主题）" grub-theme grub-notheme systemd-boot
  BOOT="$PICKED"

  pick_one "语言环境（默认 英文）" en_US zh_CN
  LOCALE="$PICKED"

  pick_one "输入法（默认 IBus+Rime）" ibus fcitx5
  INPUT="$PICKED"

  pick_one "镜像源（默认 中科大）" ustc tuna nju
  MIRROR="$PICKED"

  pick_one "默认 Shell（默认 zsh）" zsh bash fish
  USERSHELL="$PICKED"

  pick_multi "系统模块（默认开前5个）" "auto-update clean nix-command zram fonts" \
    auto-update clean nix-command zram fonts nopwdtodesktop vm-debug
  SYSTEM_MODULES="$PICKED_MULTI"

  pick_multi "进阶模块（默认全关）" "" secrets impermanence backup security
  ADVANCED="$PICKED_MULTI"
}

# ---------- 展示当前选择 ----------
show_selection() {
  say ""
  say "${C_BOLD}当前选择：${C_RESET}"
  say "  桌面环境 : ${DESKTOP:-xfce}"
  say "  引导加载 : ${BOOT:-grub-theme}"
  say "  语言环境 : ${LOCALE:-en_US}"
  say "  输入法   : ${INPUT:-ibus}"
  say "  镜像源   : ${MIRROR:-ustc}"
  say "  Shell    : ${USERSHELL:-zsh}"
  say "  系统模块 : ${SYSTEM_MODULES:-auto-update clean nix-command zram fonts}"
  say "  进阶模块 : ${ADVANCED:-（无）}"
  say ""
}
