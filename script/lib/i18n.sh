# UTNixOS_Pro 中英双语支持（script/lib/i18n.sh）
#
# 启动时自动选择语言，优先级：
#   1. UTNIXOS_PRO_LANG=zh|en   显式指定（最高优先级，可用来强制语言）
#   2. TERM=linux（Linux 虚拟控制台）→ 英文：控制台位图字体通常不含中文字形，
#      显示中文会变成方块字。这也是本模块存在的核心原因之一。
#   3. 按 LC_ALL / LANG 自动检测：zh* → 中文，其余 → 英文
#
# 使用：所有面向用户的文本都写成字典键，调用时 _t <键> [printf参数...]。
#   例：info up_doing "$CFG"   （键的格式串里用 %s 引用传入的参数）
# 输出辅助函数 say/info/ok/warn/die/prompt 已封装 _t：第一个参数当键，其余当参数。
# 传入非键的普通字符串时会原样输出（_t 找不到键就返回原串）。
#
# 依赖：无（env.sh 的颜色变量在 util.sh 中使用，与本模块无关）。
# 由 script/main.sh 自动加载；install.sh 引导阶段用自身的最小实现（见 install.sh）。

# ---------- 语言检测 ----------
detect_lang() {
  local forced="${UTNIXOS_PRO_LANG:-}"
  # 1) 显式指定
  if [[ -n "$forced" ]]; then
    case "$forced" in
      zh|zh_*|cn|Chinese|chinese) echo zh ;;
      *) echo en ;;
    esac
    return
  fi
  # 2) Linux 虚拟控制台（TERM=linux）字体一般不含中文字形（显示成方块）→ 英文
  if [[ "${TERM:-}" == "linux" ]]; then echo en; return; fi
  # 3) 按 locale 自动选择
  local lc="${LC_ALL:-${LANG:-}}"
  case "$lc" in
    zh*|zh_*) echo zh ;;
    *) echo en ;;
  esac
}

if [[ -z "${LANG_UI:-}" ]]; then
  LANG_UI="$(detect_lang)"
  export LANG_UI
fi

# ---------- 翻译字典（键两侧都定义；格式串用 %s 引用 _t 的参数）----------
# 注意：值里的 % 必须成对（printf 转义），含 $ 需转义或用 %s 传入。
declare -A L10N_EN=(
  # main.sh 帮助 / 参数路由
  [unknown_arg]="Unknown argument: %s (available: install / update / menu / rollback)"
  [help_usage]="Usage:"
  [help_install]="  install.sh                    # no args: live env = install / installed system = dashboard"
  [help_install_cmd]="  install.sh install            # fresh install (NixOS live env)"
  [help_update]="  install.sh update             # update system (sync latest code + rebuild)"
  [help_menu]="  install.sh menu               # select/change modules (desktop, shell, etc.)"
  [help_rollback]="  install.sh rollback           # system rollback (--rollback is a synonym)"
  [help_no_apple]="  --no-apple                    extra flag: skip downloading/deploying badapple.mp4 (easter egg unavailable)"
  [help_ut]="  the ut command (built into the installed system) is equivalent to sudo install.sh"
  [help_curl]="  install via curl: curl -L %s | bash"
  [help_curl_rollback]="  rollback via curl (works even if the local scripts are broken):"
  [help_curl_rollback_cmd]="    curl -L %s | sudo bash -s -- --rollback"

  # util.sh 菜单提示
  [menu_choose]="Choose [1-%s] (Enter = default 1st): "
  [multi_suffix]="(enter a number to toggle [x]/[ ], Enter to confirm)"
  [multi_prompt]="> "

  # selection.sh 模块选择
  [nofile_cfg]="File not found: %s"
  [apply_write]="Writing selection to %s ..."
  [apply_done]="configuration.nix updated"
  [state_restored]="Restored previous module selection"
  [menu_intro]="Please choose the modules to enable (only one per category, to avoid conflicts)"
  [menu_hint]="Hint: press Enter to use the default value / first item"
  [t_desktop]="Desktop environment (default xfce)"
  [t_boot]="Boot loader (default GRUB/UEFI; GRUB BIOS needs a target disk)"
  [t_grub_theme_q]="Enable GRUB theme (Touhou)? [Y/n] "
  [t_grub_disk_list]="Detected disks (confirm which one GRUB/BIOS installs to):"
  [t_grub_disk_manual]="Enter the disk GRUB/BIOS should install to, e.g. /dev/sda (Enter = /dev/sda): "
  [t_grub_disk_set]="GRUB target disk: %s"
  [t_grub_disk_missing]="Warning: disk %s does not exist, please verify before continuing"
  [t_grub_disk_invalid]="Warning: %s is not a valid disk path, falling back to /dev/sda"
  [t_locale]="Locale (default English)"
  [t_input]="Input method (default IBus+Rime)"
  [t_mirror]="Mirror (default USTC)"
  [t_shell]="Default shell (default zsh)"
  [t_sysmods]="System modules (first 6 on by default)"
  [t_advmods]="Advanced modules (all off by default)"
  [cur_selection]="Current selection:"
  [lab_desktop]="Desktop"
  [lab_boot]="Boot loader"
  [lab_grub_theme]="GRUB theme"
  [lab_grub_device]="GRUB target disk"
  [lab_locale]="Locale"
  [lab_input]="Input method"
  [lab_mirror]="Mirror"
  [lab_shell]="Shell"
  [lab_sysmods]="System modules"
  [lab_advmods]="Advanced modules"
  [val_none]="(none)"

  # 菜单选项名称（opt_<模块名>；util.sh 的 opt_label 优先用这里，找不到显示原始名）
  # 桌面
  [opt_xfce]="XFCE (lightweight)"
  [opt_gnome]="GNOME (modern)"
  [opt_kde]="KDE Plasma (customizable)"
  [opt_lxqt]="LXQt (ultra-light)"
  [opt_hyprland]="Hyprland (tiling Wayland)"
  [opt_cosmic]="COSMIC (System76)"
  # 引导
  ["opt_grub-uefi"]="GRUB (UEFI)"
  ["opt_grub-bios"]="GRUB (BIOS/legacy, needs target disk)"
  ["opt_systemd-boot"]="systemd-boot (UEFI only, fast)"
  # 语言 / 输入法 / 镜像 / Shell
  [opt_en_US]="English (US)"
  [opt_zh_CN]="Chinese (China)"
  [opt_ibus]="IBus + Rime"
  [opt_fcitx5]="Fcitx5 (recommended for KDE)"
  [opt_ustc]="USTC mirror"
  [opt_tuna]="TUNA mirror (Tsinghua)"
  [opt_nju]="NJU mirror"
  [opt_sjtu]="SJTU mirror (Shanghai Jiao Tong)"
  [opt_zsh]="Zsh (+ Oh My Zsh)"
  [opt_bash]="Bash"
  [opt_fish]="Fish"
  # 系统模块
  ["opt_auto-update"]="Auto update (daily sync + rebuild)"
  [opt_clean]="Auto clean (daily GC)"
  ["opt_nix-command"]="Flakes experimental feature"
  [opt_zram]="ZRAM memory compression"
  [opt_fonts]="Unified fonts (Noto + Nerd Font)"
  [opt_webui]="Web management panel (127.0.0.1:8090)"
  [opt_nopwdtodesktop]="Passwordless auto-login"
  ["opt_vm-debug"]="VM debug (headless boot)"
  # 进阶模块
  [opt_secrets]="Secrets (sops-nix)"
  [opt_impermanence]="Root non-persistence (impermanence)"
  [opt_backup]="Scheduled backup (restic)"
  [opt_security]="Security hardening (fail2ban)"

  # commands/dashboard.sh 管理面板
  [dash_root]="Dashboard requires root; use: sudo install.sh or run ut directly"
  [dash_noflake]="No flake.nix under /etc/nixos; dashboard rebuild/update is unavailable"
  [dash_noflake2]="(rollback does not depend on config, still available)"
  [dash_title]="========== UTNixOS_Pro Management Menu =========="
  [dash_opt1]="  1) Rebuild system (nixos-rebuild switch)"
  [dash_opt2]="  2) Clean build garbage (nix-collect-garbage -d)"
  [dash_opt3]="  3) Select/change modules (desktop/boot/shell/input etc.)"
  [dash_opt4]="  4) Update config (sync latest code from GitHub + rebuild)"
  [dash_opt5]="  5) Update Flake (nix flake update all inputs + rebuild)"
  [dash_opt6]="  6) System rollback (choose a previous generation)"
  [dash_opt7]="  7) Exit"
  [dash_choose]="Choose [1-7]: "
  [rebuild_doing]="Rebuilding system..."
  [rebuild_done]="Rebuild complete!"
  [dash_gc]="Cleaning build garbage (keeping last 7 days of history)..."
  [dash_gc_done]="Cleaning complete!"
  [dash_flake_update]="Updating flake.lock (nix flake update)..."
  [dash_flake_done]="Flake updated and rebuilt!"
  [dash_bye]="Goodbye!"
  [dash_invalid]="Invalid choice: %s"

  # commands/install.sh 全新安装
  [inst_root]="Install mode requires root (NixOS live env is root by default)"
  [inst_check_mount]="Checking mount points..."
  [inst_mount_missing]="The system partition does not seem to be mounted at %s\nPlease run first: mount /dev/your-root-partition %s"
  [inst_boot_mounted]="Boot partition detected as mounted"
  [inst_boot_warn]="No %s/boot or %s/boot/efi detected (ignorable for BIOS/MBR)"
  [inst_no_nixos_install]="nixos-install not found; make sure you are in the NixOS live env"
  [inst_no_gen_cfg]="nixos-generate-config not found"
  [inst_confirm]="Confirm the above selection and start installation? [y/N] "
  [inst_cancel]="Cancelled"
  [inst_prep]="Preparing UTNixOS_Pro config..."
  [inst_reuse]="Reusing already-fetched code: %s"
  [inst_clone_fail]="git clone failed, please check your network"
  [inst_dl_fail]="Download failed"
  [inst_gen_hw]="Generating hardware-configuration.nix for this machine ..."
  [inst_deploy]="Deploying config files to %s ..."
  [inst_start]="Starting system installation (the download may take a while, please be patient)..."
  [inst_done]="Installation complete!"
  [inst_step1]="  1. Run reboot to restart"
  [inst_step2]="  2. Log in with reimilia / 123456, then run passwd immediately to change the password"
  [inst_step3]="  3. Manage the system later: ut (or sudo bash /etc/nixos/install.sh)"

  # commands/menu.sh 更换模块
  [menu_root]="Module management requires root; use: sudo bash install.sh menu"
  [noflake]="No flake.nix under /etc/nixos; doesn't look like a system installed by this script?"
  [menu_confirm]="Confirm changes and rebuild the system? [y/N] "
  [menu_cancel]="Cancelled; configuration.nix was modified but not rebuilt (you can run nixos-rebuild switch manually)"
  [menu_done]="Module switch complete!"

  # commands/rollback.sh 系统回滚
  [roll_no_profile]="System profile not found: %s"
  [roll_no_read]="Unable to read generations"
  [roll_current_gen]="Current system generations:"
  [roll_current_run]="Currently running : %s"
  [roll_unknown]="unknown"
  [roll_prompt]="Enter the generation number to roll back to (Enter = roll back to the previous version): "
  [roll_exec]="Running nixos-rebuild switch --rollback (roll back to the previous version)..."
  [roll_switch_gen]="Switching system profile to generation %s ..."
  [roll_activate]="Activating that generation ..."
  [roll_done]="Rollback complete! If you still have boot issues, choose another generation in the GRUB menu at reboot"

  # commands/update.sh 更新配置
  [upd_root]="Update mode requires root; use: sudo bash install.sh update"
  [upd_sync]="Syncing latest code from GitHub..."
  [upd_fetch_fail]="git fetch failed (network issue?), will use the existing local code"
  [upd_reset_fail]="git reset failed, continuing with the existing code"
  [upd_dl_fail]="Failed to download the latest code"
  [upd_code_ok]="Code updated (old config backed up at %s; you can delete it once confirmed)"
  [upd_rechoose]="Do you want to re-select modules? (e.g. change desktop) [y/N] "
  [upd_rebuild]="Rebuilding system (nixos-rebuild switch)..."
  [upd_done]="System update complete!"

  # easteregg.sh 彩蛋
  [egg_notfound1]="✿ badapple.mp4 not found"
  [egg_notfound2]="  (systems installed with --no-apple do not deploy this file)"
  [egg_notfound3]="  to add it: put badapple.mp4 in /etc/nixos/media/ and run ut to rebuild"
  [egg_playing]="✿ Touhou! Bad Apple!! playing~ (Ctrl+C to return to the menu)"
  [egg_noplayer_nix]="  no player found, using nix run to temporarily fetch mpv..."
  [egg_noplayer_found]="  no player found, video file is at: %s"
  [egg_install_mpv]="  install mpv, then type touhou to play"
)

declare -A L10N_ZH=(
  # main.sh 帮助 / 参数路由
  [unknown_arg]="未知参数：%s（可用：install / update / menu / rollback）"
  [help_usage]="用法："
  [help_install]="  install.sh                    # 无参数：live环境=安装 / 已装系统=管理面板"
  [help_install_cmd]="  install.sh install            # 全新安装（NixOS live 环境）"
  [help_update]="  install.sh update             # 更新系统（同步最新代码并重建）"
  [help_menu]="  install.sh menu               # 选择/更换模块（换桌面、Shell 等）"
  [help_rollback]="  install.sh rollback           # 系统回滚（--rollback 同义）"
  [help_no_apple]="  --no-apple                    附加参数：不下载/不部署 badapple.mp4（彩蛋将不可用）"
  [help_ut]="  ut 命令（安装后系统内置）等价于 sudo install.sh"
  [help_curl]="  curl 方式安装：curl -L %s | bash"
  [help_curl_rollback]="  curl 方式回滚（本地脚本坏了也能用）："
  [help_curl_rollback_cmd]="    curl -L %s | sudo bash -s -- --rollback"

  # util.sh 菜单提示
  [menu_choose]="请选择 [1-%s]（回车=默认第1项）: "
  [multi_suffix]="（输入序号切换 [x]/[ ]，回车确认）"
  [multi_prompt]="> "

  # selection.sh 模块选择
  [nofile_cfg]="找不到 %s"
  [apply_write]="正在把选择写入 %s ..."
  [apply_done]="configuration.nix 已更新"
  [state_restored]="已恢复上次的模块选择"
  [menu_intro]="请选择要启用的模块（同类只能选一个，避免冲突）"
  [menu_hint]="提示：直接回车使用默认值/第1项"
  [t_desktop]="桌面环境（默认 xfce）"
  [t_boot]="引导加载器（默认 GRUB/UEFI；GRUB BIOS 需指定目标磁盘）"
  [t_grub_theme_q]="启用 GRUB 主题（东方）？[Y/n] "
  [t_grub_disk_list]="检测到以下磁盘（确认 GRUB/BIOS 要装到哪块）:"
  [t_grub_disk_manual]="输入 GRUB/BIOS 要安装到的磁盘，如 /dev/sda（回车默认 /dev/sda）: "
  [t_grub_disk_set]="GRUB 目标磁盘：%s"
  [t_grub_disk_missing]="警告：磁盘 %s 不存在，请确认无误后再继续"
  [t_grub_disk_invalid]="警告：%s 不是合法的磁盘路径，已回退为 /dev/sda"
  [t_locale]="语言环境（默认 英文）"
  [t_input]="输入法（默认 IBus+Rime）"
  [t_mirror]="镜像源（默认 中科大）"
  [t_shell]="默认 Shell（默认 zsh）"
  [t_sysmods]="系统模块（默认开前6个）"
  [t_advmods]="进阶模块（默认全关）"
  [cur_selection]="当前选择："
  [lab_desktop]="桌面环境"
  [lab_boot]="引导加载"
  [lab_grub_theme]="GRUB 主题"
  [lab_grub_device]="GRUB 目标磁盘"
  [lab_locale]="语言环境"
  [lab_input]="输入法"
  [lab_mirror]="镜像源"
  [lab_shell]="Shell"
  [lab_sysmods]="系统模块"
  [lab_advmods]="进阶模块"
  [val_none]="（无）"

  # 菜单选项名称（opt_<模块名>；util.sh 的 opt_label 优先用这里，找不到显示原始名）
  # 桌面
  [opt_xfce]="XFCE（轻量经典桌面）"
  [opt_gnome]="GNOME（现代简洁桌面）"
  [opt_kde]="KDE Plasma（可定制桌面）"
  [opt_lxqt]="LXQt（极轻量桌面）"
  [opt_hyprland]="Hyprland（平铺 Wayland）"
  [opt_cosmic]="COSMIC（System76 新桌面）"
  # 引导
  ["opt_grub-uefi"]="GRUB（UEFI 启动，兼容性最好）"
  ["opt_grub-bios"]="GRUB（BIOS/传统启动，需指定目标磁盘）"
  ["opt_systemd-boot"]="systemd-boot（仅 UEFI，启动最快，不支持主题）"
  # 语言 / 输入法 / 镜像 / Shell
  [opt_en_US]="英文（美国）"
  [opt_zh_CN]="中文（中国）"
  [opt_ibus]="IBus + Rime（拼音）"
  [opt_fcitx5]="Fcitx5（KDE 用户推荐）"
  [opt_ustc]="中科大镜像"
  [opt_tuna]="清华镜像"
  [opt_nju]="南京大学镜像"
  [opt_sjtu]="上海交大镜像"
  [opt_zsh]="Zsh（带 Oh My Zsh）"
  [opt_bash]="Bash"
  [opt_fish]="Fish"
  # 系统模块
  ["opt_auto-update"]="自动更新（每天同步代码并重建）"
  [opt_clean]="自动清理垃圾（每天 GC）"
  ["opt_nix-command"]="Flakes 实验特性（新版 nix 命令）"
  [opt_zram]="ZRAM 内存压缩"
  [opt_fonts]="统一字体（Noto + Nerd Font）"
  [opt_webui]="Web 管理面板（127.0.0.1:8090）"
  [opt_nopwdtodesktop]="免密自动登录（开机直达桌面）"
  ["opt_vm-debug"]="VM 调试（无头启动，普通用户勿开）"
  # 进阶模块
  [opt_secrets]="密钥管理（sops-nix）"
  [opt_impermanence]="根分区不持久化（impermanence）"
  [opt_backup]="定时备份（restic）"
  [opt_security]="安全加固（fail2ban）"

  # commands/dashboard.sh 管理面板
  [dash_root]="管理面板需要 root，请用：sudo install.sh 或直接运行 ut"
  [dash_noflake]="/etc/nixos 下没有 flake.nix，面板的重建/更新功能不可用"
  [dash_noflake2]="（回滚功能不依赖配置，可继续使用）"
  [dash_title]="========== UTNixOS_Pro 管理菜单 =========="
  [dash_opt1]="  1) 重建系统（nixos-rebuild switch）"
  [dash_opt2]="  2) 清理构建垃圾（nix-collect-garbage -d）"
  [dash_opt3]="  3) 选择/更换模块（桌面/引导/Shell/输入法等）"
  [dash_opt4]="  4) 更新配置（从 GitHub 同步最新代码 + 重建）"
  [dash_opt5]="  5) 更新 Flake（nix flake update 所有输入 + 重建）"
  [dash_opt6]="  6) 系统回滚（选择之前的 generation）"
  [dash_opt7]="  7) 退出"
  [dash_choose]="请选择 [1-7]: "
  [rebuild_doing]="开始重建系统..."
  [rebuild_done]="重建完成！"
  [dash_gc]="清理构建垃圾（保留最近7天的历史）..."
  [dash_gc_done]="清理完成！"
  [dash_flake_update]="更新 flake.lock（nix flake update）..."
  [dash_flake_done]="Flake 更新并重建完成！"
  [dash_bye]="再见！"
  [dash_invalid]="无效选择：%s"

  # commands/install.sh 全新安装
  [inst_root]="安装模式需要 root 权限（NixOS live 环境默认就是 root）"
  [inst_check_mount]="检查挂载情况..."
  [inst_mount_missing]="系统分区似乎没有挂载到 %s\n请先执行：mount /dev/你的根分区 %s"
  [inst_boot_mounted]="检测到引导分区已挂载"
  [inst_boot_warn]="没检测到 %s/boot 或 %s/boot/efi（BIOS/MBR 方式可忽略）"
  [inst_no_nixos_install]="没找到 nixos-install，请确认你在 NixOS live 环境里"
  [inst_no_gen_cfg]="没找到 nixos-generate-config"
  [inst_confirm]="确认以上选择并开始安装？[y/N] "
  [inst_cancel]="已取消"
  [inst_prep]="准备 UTNixOS_Pro 配置..."
  [inst_reuse]="复用已拉取的代码：%s"
  [inst_clone_fail]="git clone 失败，请检查网络"
  [inst_dl_fail]="下载失败"
  [inst_gen_hw]="生成这台机器的 hardware-configuration.nix ..."
  [inst_deploy]="部署配置文件到 %s ..."
  [inst_start]="开始安装系统（下载可能需要较长时间，请耐心等待）..."
  [inst_done]="安装完成！"
  [inst_step1]="  1. 输入 reboot 重启"
  [inst_step2]="  2. 用 reimilia / 123456 登录，然后立即执行 passwd 修改密码"
  [inst_step3]="  3. 以后管理系统：ut（或 sudo bash /etc/nixos/install.sh）"

  # commands/menu.sh 更换模块
  [menu_root]="模块管理需要 root，请用：sudo bash install.sh menu"
  [noflake]="/etc/nixos 下没有 flake.nix，看起来不是由本脚本安装的系统？"
  [menu_confirm]="确认修改并重建系统？[y/N] "
  [menu_cancel]="已取消，configuration.nix 已修改但未重建（可手动 nixos-rebuild switch）"
  [menu_done]="模块切换完成！"

  # commands/rollback.sh 系统回滚
  [roll_no_profile]="找不到系统 profile：%s"
  [roll_no_read]="无法读取 generations"
  [roll_current_gen]="当前系统 generations："
  [roll_current_run]="当前运行 : %s"
  [roll_unknown]="未知"
  [roll_prompt]="输入要回滚到的 generation 编号（直接回车 = 回滚到上一个版本）: "
  [roll_exec]="执行 nixos-rebuild switch --rollback（回滚到上一个版本）..."
  [roll_switch_gen]="切换系统 profile 到 generation %s ..."
  [roll_activate]="激活该 generation ..."
  [roll_done]="回滚完成！如果引导还有问题，重启时可以在 GRUB 菜单里选择其他 generation"

  # commands/update.sh 更新配置
  [upd_root]="更新模式需要 root，请用：sudo bash install.sh update"
  [upd_sync]="从 GitHub 同步最新代码..."
  [upd_fetch_fail]="git fetch 失败（网络问题？），将使用本地已有代码"
  [upd_reset_fail]="git reset 失败，继续使用现有代码"
  [upd_dl_fail]="下载最新代码失败"
  [upd_code_ok]="代码已更新（旧配置备份在 %s，确认没问题后可删除）"
  [upd_rechoose]="是否要重新选择模块？（比如换桌面环境）[y/N] "
  [upd_rebuild]="开始重建系统（nixos-rebuild switch）..."
  [upd_done]="系统更新完成！"

  # easteregg.sh 彩蛋
  [egg_notfound1]="✿ 没有找到 badapple.mp4"
  [egg_notfound2]="  （用 --no-apple 安装的系统不会部署该文件）"
  [egg_notfound3]="  想补上的话：把 badapple.mp4 放到 /etc/nixos/media/ 再运行 ut 重建即可"
  [egg_playing]="✿ 東方萃夢想！Bad Apple!! 开始播放~ (Ctrl+C 可以切回菜单)"
  [egg_noplayer_nix]="  没有找到播放器，用 nix run 临时拉取 mpv 播放..."
  [egg_noplayer_found]="  找不到任何播放器，视频文件在：%s"
  [egg_install_mpv]="  安装 mpv 后输入 touhou 就能播了"
)

# ---------- 翻译函数 ----------
# _t <键> [printf参数...]：返回当前语言下的文本；找不到键或键为空就原样返回。
_t() {
  local key="$1"; shift
  [[ -z "$key" ]] && return 0   # 空串：避免非法空数组下标（say "" 等）
  local fmt
  if [[ "$LANG_UI" == "zh" ]]; then
    fmt="${L10N_ZH[$key]:-}"
    [[ -z "$fmt" ]] && fmt="${L10N_EN[$key]:-$key}"
  else
    fmt="${L10N_EN[$key]:-$key}"
  fi
  printf "$fmt" "$@"
}
