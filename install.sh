#!/usr/bin/env bash
# ============================================================================
#  UTNixOS_Pro - 唯一脚本（单文件自包含）
#
#  设计（去 Bash 脚本化之后）：
#    - 系统的日常「配置与管理」全部交给 Web 管理面板
#      （Go 后端，systemd 守护进程 utnixos-pro-webui 常驻，
#       直接读写 /etc/nixos 下的配置文件；WebUI 为系统内置、不可关闭）
#    - install.sh 是仓库里唯一保留的脚本，只承担三件事：
#        1) 全新安装（交互式向导：引导/桌面/语言/输入法/镜像/Shell/模块…）
#        2) 修复配置（repair）：/etc/nixos 损坏时重建并保留机器本地文件
#        3) UT紧急回滚（rollback）：系统 generations 应急回滚
#      其余管理动作（重建/更新/GC/装包/换模块/看日志）请用 `ut` 打开 WebUI：
#          ut          → 快捷启动 Web 管理面板 http://127.0.0.1:8090
#
#  本文件特性：
#    - 中英双语：Linux 虚拟控制台（TERM=linux，位图字体无中文字形）自动切英文，
#      其余按 LC_ALL/LANG 自动检测（zh* → 中文），也可 UTNIXOS_PRO_LANG=zh|en 强制
#    - 完全自包含，单文件即可执行；需要「配置源码」时（安装/修复）才从
#      GitHub 拉取整个仓库（git clone，失败回退 tarball），支持代理透传
#    - 彩蛋：安装向导与入口菜单输入 touhou 播放 Bad Apple!!
#
#  用法：
#    bash install.sh                      # 交互入口：安装 / 修复配置 / UT紧急回滚
#    bash install.sh install              # 全新安装（NixOS live 环境）
#    bash install.sh repair               # 修复 /etc/nixos（配置损坏时）
#    bash install.sh rollback             # UT紧急回滚（--rollback 同义）
#    curl -L <install.sh> | sudo bash -s -- rollback   # 脚本/配置全坏也能应急回滚
#    bash install.sh help                 # 查看帮助
#
#  结构（同文件内分节）：
#    环境与路径 → 语言检测与 i18n 字典 → 通用工具(输出/菜单/ASCII) →
#    彩蛋 → 模块选择(改 configuration.nix / home-manager.nix) →
#    安装向导 → 修复配置 → UT紧急回滚 → 入口菜单/命令路由
# ============================================================================
set -euo pipefail

# ============================================================================
# 环境与路径（支持环境变量覆盖：UTNIXOS_PRO_GIT_URL / TARBALL_URL 等）
# ============================================================================
GIT_URL="${UTNIXOS_PRO_GIT_URL:-https://github.com/Reimilia617/UTNixOS_Pro.git}"
TARBALL_URL="${UTNIXOS_PRO_TARBALL_URL:-https://github.com/Reimilia617/UTNixOS_Pro/archive/refs/heads/main.tar.gz}"
RAW_URL="${UTNIXOS_PRO_RAW_URL:-https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh}"
INSTALL_DIR="/etc/nixos"            # 已安装系统上的配置目录
MOUNT_ROOT="/mnt"                   # live 环境挂载点
HOSTNAME="reimilia"                 # 主机名（默认）
STATE_FILE=".utnixos-pro-selection" # 选择状态文件（相对配置目录）

# 镜像源 URL（与 modules/mirrors/*.nix 保持一致）
declare -A MIRROR_URLS=(
  [ustc]="https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org/"
  [tuna]="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org/"
  [nju]="https://mirrors.nju.edu.cn/nix-channels/store https://cache.nixos.org/"
  [sjtu]="https://mirror.sjtu.edu.cn/nix-channels/store https://cache.nixos.org/"
)

# 颜色
C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
C_CYAN=$'\e[36m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'

# 安装时默认账号（可交互自定义；密码会以 sha512 哈希写入 modules/users/*.nix）
DEFAULT_USER="reimilia"
DEFAULT_PASS="123456"

# ============================================================================
# 源码目录定位
#
# 安装 / 修复都需要「完整仓库」内容（flake.nix + modules/ + …）来部署或重建
# /etc/nixos。如果本脚本是从一个完整仓库里执行的（例如 git clone 后本地运行，
# 或 /etc/nixos 里的 install.sh），就把 SCRIPT_SRC 指向它，优先复用、避免每次都
# 重新从 GitHub 拉取；curl|bash（$0=bash、旁边没有仓库）时保持为空 → 用到时再拉。
# ============================================================================
SCRIPT_SRC=""
if [[ "$0" == *"install.sh" && -f "$0" ]]; then
  local_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  if [[ -n "$local_dir" && -f "$local_dir/flake.nix" && -f "$local_dir/install.sh" ]]; then
    SCRIPT_SRC="$local_dir"
  fi
fi
if [[ -z "$SCRIPT_SRC" && -f "./flake.nix" && -f "./install.sh" ]]; then
  SCRIPT_SRC="$(pwd)"
fi
export SCRIPT_SRC

# ============================================================================
# 语言检测
# ============================================================================
detect_lang() {
  local forced="${UTNIXOS_PRO_LANG:-}"
  if [[ -n "$forced" ]]; then
    case "$forced" in
      zh|zh_*|cn|Chinese|chinese) echo zh ;;
      *) echo en ;;
    esac
    return
  fi
  # Linux 虚拟控制台位图字体通常不含中文字形（显示成方块）→ 英文
  [[ "${TERM:-}" == "linux" ]] && { echo en; return; }
  case "${LC_ALL:-${LANG:-}}" in
    zh*|zh_*) echo zh ;;
    *) echo en ;;
  esac
}
LANG_UI="$(detect_lang)"
export LANG_UI

# ============================================================================
# 中英双语字典（键两侧都定义；格式串用 %s 引用参数）
# ============================================================================
declare -A L10N_EN=(
  # 入口菜单 / 帮助
  [unknown_arg]="Unknown argument: %s (available: install / repair / rollback / help)"
  [help_usage]="Usage:"
  [help_install]="  bash install.sh                  # interactive entry: install / repair / rollback"
  [help_install_cmd]="  bash install.sh install             # fresh install (NixOS live env)"
  [help_repair]="  bash install.sh repair              # repair /etc/nixos: keep machine files, pull latest code, rebuild"
  [help_rollback]="  bash install.sh rollback           # UT Emergency Rollback (--rollback is a synonym)"
  [help_no_apple]="  --no-apple                    extra flag: skip downloading/deploying badapple.mp4 (easter egg unavailable)"
  [help_ut]="  the ut command (built into the installed system) quickly launches the Web panel"
  [help_curl]="  install via curl: curl -L %s | bash"
  [help_curl_rollback]="  emergency rollback via curl (works even if local scripts/config are broken):"
  [help_curl_rollback_cmd]="    curl -L %s | sudo bash -s -- --rollback"
  [entry_welcome]="Welcome! Choose an action:"
  [entry_opt_install]=" 1) Fresh install (NixOS live env)"
  [entry_opt_repair]=" 2) Repair /etc/nixos config (recovery)"
  [entry_opt_rollback]=" 3) UT Emergency Rollback"
  [entry_opt_quit]=" q) Quit"
  [entry_prompt]="Choose [1-3/q] (Enter = fresh install): "
  [entry_invalid]="Invalid choice: %s"
  [entry_hint_live]="Detected a NixOS live environment (fresh install is ready)."
  [entry_hint_installed]="Detected an installed system: daily configuration is managed from the Web panel."
  [entry_hint_ut]="  Run  ut  to open the Web management panel (http://127.0.0.1:8090)"
  [entry_help_hint]="  (install.sh here is only for install / repair / emergency rollback)"
  [oldcmd_gone]="'%s' is no longer a separate command: it is managed from the Web panel (run: ut),\n  or here as: install.sh repair / install.sh rollback"
  [rebuild_doing]="Rebuilding system..."

  # 通用菜单
  [menu_choose]="Choose [1-%s] (Enter = default 1st): "
  [multi_suffix]="(enter a number to toggle [x]/[ ], Enter to confirm)"
  [multi_prompt]="> "

  # 模块选择
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
  [t_sysmods]="System modules (first 5 on by default; Web panel is always built-in)"
  [t_advmods]="Advanced modules (all off by default)"
  [cur_selection]="Current selection:"
  [lab_desktop]="Desktop"
  [lab_boot]="Boot loader"
  [lab_user]="System user"
  [lab_grub_theme]="GRUB theme"
  [lab_grub_device]="GRUB target disk"
  [lab_locale]="Locale"
  [lab_input]="Input method"
  [lab_mirror]="Mirror"
  [lab_shell]="Shell"
  [lab_sysmods]="System modules"
  [lab_advmods]="Advanced modules"
  [val_none]="(none)"

  # 菜单选项名称
  [opt_xfce]="XFCE (lightweight)"
  [opt_gnome]="GNOME (modern)"
  [opt_kde]="KDE Plasma (customizable)"
  [opt_lxqt]="LXQt (ultra-light)"
  [opt_hyprland]="Hyprland (tiling Wayland)"
  [opt_cosmic]="COSMIC (System76)"
  ["opt_grub-uefi"]="GRUB (UEFI)"
  ["opt_grub-bios"]="GRUB (BIOS/legacy, needs target disk)"
  ["opt_systemd-boot"]="systemd-boot (UEFI only, fast)"
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
  [opt_auto-update]="Auto update (daily sync + rebuild)"
  [opt_clean]="Auto clean (daily GC)"
  ["opt_nix-command"]="Flakes experimental feature"
  [opt_zram]="ZRAM memory compression"
  [opt_fonts]="Unified fonts (Noto + Nerd Font)"
  [opt_nopwdtodesktop]="Passwordless auto-login"
  ["opt_vm-debug"]="VM debug (headless boot)"
  [opt_secrets]="Secrets (sops-nix)"
  [opt_impermanence]="Root non-persistence (impermanence)"
  [opt_backup]="Scheduled backup (restic)"
  [opt_security]="Security hardening (fail2ban)"

  # 安装向导
  [inst_root]="Install mode requires root (NixOS live env is root by default)"
  [inst_check_mount]="Checking mount points..."
  [inst_mount_missing]="The system partition does not seem to be mounted at %s\nPlease run first: mount /dev/your-root-partition %s"
  [inst_boot_mounted]="Boot partition detected as mounted"
  [inst_boot_efi_misplaced]="Warning: the ESP is mounted at %s/boot/efi, but NixOS GRUB/systemd-boot looks for it at /boot by default. Please mount the ESP at %s/boot instead (or set boot.loader.efi.efiSysMountPoint = \"/boot/efi\" in configuration.nix)"
  [inst_boot_warn]="No %s/boot detected (UEFI: mount the ESP at /boot; ignorable for BIOS/MBR)"
  [inst_no_nixos_install]="nixos-install not found; make sure you are in the NixOS live env"
  [inst_no_gen_cfg]="nixos-generate-config not found"
  [inst_confirm]="Confirm the above selection and start installation? [y/N] "
  [inst_cancel]="Cancelled"
  [inst_prep]="Preparing UTNixOS_Pro config..."
  [inst_reuse]="Reusing already-fetched code: %s"
  [inst_fetch_doing]="Fetching the latest UTNixOS_Pro code from GitHub..."
  [inst_proxy]="Using proxy: %s"
  [inst_clone_fail]="git clone failed, please check your network"
  [inst_dl_fail]="Download failed"
  [inst_gen_hw]="Generating hardware-configuration.nix for this machine ..."
  [inst_deploy]="Deploying config files to %s ..."
  [inst_start]="Starting system installation (the download may take a while, please be patient)..."
  [inst_done]="Installation complete!"
  [inst_step1]="  1. Run reboot to restart"
  [inst_step2]="  2. Log in with %s / %s, then run passwd immediately to change the password"
  [inst_step2_custom]="  2. Log in with the username/password you just set (user: %s), then run passwd immediately"
  [inst_step3]="  3. Manage the system later: run ut to open the Web panel (http://127.0.0.1:8090)"
  [ident_prompt_user]="System username (Enter = %s): "
  [ident_user_invalid]="Invalid username: %s (use lowercase letters / digits / _ / -, max 32)"
  [ident_prompt_pass]="Initial password for %s (input is hidden; Enter = %s): "
  [ident_pass_short]="Password too short (min 6 chars), please retype."
  [ident_pass_confirm]="Repeat the password: "
  [ident_pass_mismatch]="Passwords do not match, please retype."
  [ident_applied]="Username/password written into the config with sed: %s"
  [ident_hash_fail]="Failed to generate a password hash (needs openssl / mkpasswd / python3)"

  # 修复配置 repair
  [repair_root]="Repair requires root; use: sudo bash install.sh repair (or: curl -L <install.sh> | sudo bash -s -- repair)"
  [repair_heading]="Repair /etc/nixos (keep machine config, pull latest code, rebuild)"
  [repair_start]="Repairing /etc/nixos with the latest code (machine config preserved)..."
  [repair_backup]="Existing config backed up to %s"
  [repair_reuse]="Using already-fetched latest code: %s"
  [repair_local_stale]="Local /etc/nixos may be stale; fetching the latest code from GitHub instead"
  [repair_fetch]="Fetching latest code from GitHub..."
  [repair_fetch_fail]="Failed to fetch the latest code; /etc/nixos was NOT modified (previous config is intact)"
  [repair_no_hw]="hardware-configuration.nix not found in the backup; regenerating it for this machine..."
  [repair_no_hw_fail]="Warning: failed to regenerate hardware-configuration.nix; you may need to run nixos-generate-config manually"
  [repair_swap_fail]="Failed to rebuild /etc/nixos; the previous config was restored"
  [repair_ready]="Config repaired. Ready to rebuild."
  [repair_confirm]="Rebuild the system now (nixos-rebuild switch)? [Y/n] "
  [repair_skip]="Skipped rebuild. Run it later: sudo nixos-rebuild switch --flake /etc/nixos#reimilia"
  [repair_done]="Repair complete! Please verify ut and the Web panel work"
  [repair_webui_active]="Web panel service (utnixos-pro-webui) is running"
  [repair_webui_inactive]="Web panel service is NOT running; check: systemctl status utnixos-pro-webui / journalctl -u utnixos-pro-webui -n 30"

  # UT紧急回滚
  [roll_heading]="UT Emergency Rollback"
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

  # 彩蛋
  [egg_notfound1]="badapple.mp4 not found"
  [egg_notfound2]="  (systems installed with --no-apple do not deploy this file)"
  [egg_notfound3]="  to add it: put badapple.mp4 in /etc/nixos/media/ and rebuild from the Web panel"
  [egg_playing]="Touhou! Bad Apple!! playing~ (Ctrl+C to return to the menu)"
  [egg_noplayer_nix]="  no player found, using nix run to temporarily fetch mpv..."
  [egg_noplayer_found]="  no player found, video file is at: %s"
  [egg_install_mpv]="  install mpv, then type touhou to play"
)

declare -A L10N_ZH=(
  # 入口菜单 / 帮助
  [unknown_arg]="未知参数：%s（可用：install / repair / rollback / help）"
  [help_usage]="用法："
  [help_install]="  bash install.sh                  # 交互入口：全新安装 / 修复配置 / UT紧急回滚"
  [help_install_cmd]="  bash install.sh install             # 全新安装（NixOS live 环境）"
  [help_repair]="  bash install.sh repair              # 修复 /etc/nixos：保留机器配置，拉取最新代码重建"
  [help_rollback]="  bash install.sh rollback           # UT紧急回滚（--rollback 同义）"
  [help_no_apple]="  --no-apple                    附加参数：不下载/不部署 badapple.mp4（彩蛋将不可用）"
  [help_ut]="  ut 命令（安装后系统内置）＝快捷启动 Web 管理面板"
  [help_curl]="  curl 方式安装：curl -L %s | bash"
  [help_curl_rollback]="  curl 方式应急回滚（本地脚本/配置全坏也能用）："
  [help_curl_rollback_cmd]="    curl -L %s | sudo bash -s -- --rollback"
  [entry_welcome]="欢迎！请选择要执行的操作："
  [entry_opt_install]=" 1) 全新安装（NixOS live 环境）"
  [entry_opt_repair]=" 2) 修复配置（重建 /etc/nixos，保留机器配置）"
  [entry_opt_rollback]=" 3) UT紧急回滚"
  [entry_opt_quit]=" q) 退出"
  [entry_prompt]="请选择 [1-3/q]（回车=全新安装）: "
  [entry_invalid]="无效选择：%s"
  [entry_hint_live]="检测到 NixOS live 环境（可以开始全新安装）。"
  [entry_hint_installed]="检测到已装系统：日常配置与管理请使用 Web 管理面板。"
  [entry_hint_ut]="  运行  ut  可快捷打开 Web 管理面板（http://127.0.0.1:8090）"
  [entry_help_hint]="  （这里的 install.sh 只负责：全新安装 / 修复配置 / UT紧急回滚）"
  [oldcmd_gone]="'%s' 已不再是独立命令：它已并入 Web 管理面板（运行 ut 打开），\n  或在本脚本里用：install.sh repair / install.sh rollback"
  [rebuild_doing]="开始重建系统..."

  # 通用菜单
  [menu_choose]="请选择 [1-%s]（回车=默认第1项）: "
  [multi_suffix]="（输入序号切换 [x]/[ ]，回车确认）"
  [multi_prompt]="> "

  # 模块选择
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
  [t_sysmods]="系统模块（默认开前5个；Web 管理面板为系统内置，不再出现在此列表）"
  [t_advmods]="进阶模块（默认全关）"
  [cur_selection]="当前选择："
  [lab_desktop]="桌面环境"
  [lab_boot]="引导加载"
  [lab_user]="系统用户"
  [lab_grub_theme]="GRUB 主题"
  [lab_grub_device]="GRUB 目标磁盘"
  [lab_locale]="语言环境"
  [lab_input]="输入法"
  [lab_mirror]="镜像源"
  [lab_shell]="Shell"
  [lab_sysmods]="系统模块"
  [lab_advmods]="进阶模块"
  [val_none]="（无）"

  # 菜单选项名称
  [opt_xfce]="XFCE（轻量经典桌面）"
  [opt_gnome]="GNOME（现代简洁桌面）"
  [opt_kde]="KDE Plasma（可定制桌面）"
  [opt_lxqt]="LXQt（极轻量桌面）"
  [opt_hyprland]="Hyprland（平铺 Wayland）"
  [opt_cosmic]="COSMIC（System76 新桌面）"
  ["opt_grub-uefi"]="GRUB（UEFI 启动，兼容性最好）"
  ["opt_grub-bios"]="GRUB（BIOS/传统启动，需指定目标磁盘）"
  ["opt_systemd-boot"]="systemd-boot（仅 UEFI，启动最快，不支持主题）"
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
  [opt_auto-update]="自动更新（每天同步代码并重建）"
  [opt_clean]="自动清理垃圾（每天 GC）"
  ["opt_nix-command"]="Flakes 实验特性（新版 nix 命令）"
  [opt_zram]="ZRAM 内存压缩"
  [opt_fonts]="统一字体（Noto + Nerd Font）"
  [opt_nopwdtodesktop]="免密自动登录（开机直达桌面）"
  ["opt_vm-debug"]="VM 调试（无头启动，普通用户勿开）"
  [opt_secrets]="密钥管理（sops-nix）"
  [opt_impermanence]="根分区不持久化（impermanence）"
  [opt_backup]="定时备份（restic）"
  [opt_security]="安全加固（fail2ban）"

  # 安装向导
  [inst_root]="安装模式需要 root 权限（NixOS live 环境默认就是 root）"
  [inst_check_mount]="检查挂载情况..."
  [inst_mount_missing]="系统分区似乎没有挂载到 %s\n请先执行：mount /dev/你的根分区 %s"
  [inst_boot_mounted]="检测到引导分区已挂载"
  [inst_boot_efi_misplaced]="警告：ESP 挂在了 %s/boot/efi，但 NixOS 的 GRUB/systemd-boot 默认在 /boot 找 ESP。请把 ESP 改挂到 %s/boot（或在 configuration.nix 里设置 boot.loader.efi.efiSysMountPoint = \"/boot/efi\"）"
  [inst_boot_warn]="没检测到 %s/boot（UEFI 请把 ESP 挂到 /boot；BIOS/MBR 方式可忽略）"
  [inst_no_nixos_install]="没找到 nixos-install，请确认你在 NixOS live 环境里"
  [inst_no_gen_cfg]="没找到 nixos-generate-config"
  [inst_confirm]="确认以上选择并开始安装？[y/N] "
  [inst_cancel]="已取消"
  [inst_prep]="准备 UTNixOS_Pro 配置..."
  [inst_reuse]="复用已拉取的代码：%s"
  [inst_fetch_doing]="正在从 GitHub 获取最新 UTNixOS_Pro 代码..."
  [inst_proxy]="使用代理：%s"
  [inst_clone_fail]="git clone 失败，请检查网络"
  [inst_dl_fail]="下载失败"
  [inst_gen_hw]="生成这台机器的 hardware-configuration.nix ..."
  [inst_deploy]="部署配置文件到 %s ..."
  [inst_start]="开始安装系统（下载可能需要较长时间，请耐心等待）..."
  [inst_done]="安装完成！"
  [inst_step1]="  1. 输入 reboot 重启"
  [inst_step2]="  2. 用 %s / %s 登录，然后立即执行 passwd 修改密码"
  [inst_step2_custom]="  2. 用你刚才设置的用户名/密码登录（用户名：%s），登录后立即执行 passwd 修改密码"
  [inst_step3]="  3. 以后管理系统：运行 ut 打开 Web 管理面板（http://127.0.0.1:8090）"
  [ident_prompt_user]="系统用户名（回车默认 %s）: "
  [ident_user_invalid]="用户名不合法：%s（请用小写字母/数字/_/-，最长 32 位）"
  [ident_prompt_pass]="为 %s 设置初始密码（输入不回显，回车默认 %s）: "
  [ident_pass_short]="密码太短（至少 6 位），请重新输入。"
  [ident_pass_confirm]="再次输入密码确认: "
  [ident_pass_mismatch]="两次输入不一致，请重新输入。"
  [ident_applied]="已将用户名/密码写入配置（sed）：%s"
  [ident_hash_fail]="生成密码哈希失败（需要 openssl / mkpasswd / python3）"

  # 修复配置 repair
  [repair_root]="修复需要 root，请用：sudo bash install.sh repair（或：curl -L <install.sh> | sudo bash -s -- repair）"
  [repair_heading]="修复 /etc/nixos 配置（保留机器配置，拉取最新代码重建）"
  [repair_start]="正在用最新代码重建 /etc/nixos（保留机器配置）..."
  [repair_backup]="现有配置已备份到 %s"
  [repair_reuse]="复用已拉取的最新代码：%s"
  [repair_local_stale]="本地 /etc/nixos 可能是旧代码，改为从 GitHub 拉取最新代码"
  [repair_fetch]="正在从 GitHub 拉取最新代码..."
  [repair_fetch_fail]="拉取最新代码失败，/etc/nixos 未被修改（原配置完好）"
  [repair_no_hw]="备份里没有 hardware-configuration.nix，正在为本机重新生成..."
  [repair_no_hw_fail]="警告：生成 hardware-configuration.nix 失败，可能需要手动执行 nixos-generate-config"
  [repair_swap_fail]="重建 /etc/nixos 失败，已回滚到原配置"
  [repair_ready]="配置已修复，准备重建系统。"
  [repair_confirm]="现在重建系统（nixos-rebuild switch）？[Y/n] "
  [repair_skip]="已跳过重建，稍后执行：sudo nixos-rebuild switch --flake /etc/nixos#reimilia"
  [repair_done]="修复完成！请自行验证 ut 和 Web 管理面板是否正常"
  [repair_webui_active]="Web 管理面板服务（utnixos-pro-webui）运行中 ✓"
  [repair_webui_inactive]="Web 管理面板服务未运行，请检查：systemctl status utnixos-pro-webui / journalctl -u utnixos-pro-webui -n 30"

  # UT紧急回滚
  [roll_heading]="UT紧急回滚"
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

  # 彩蛋
  [egg_notfound1]="✿ 没有找到 badapple.mp4"
  [egg_notfound2]="  （用 --no-apple 安装的系统不会部署该文件）"
  [egg_notfound3]="  想补上的话：把 badapple.mp4 放到 /etc/nixos/media/ 再在 Web 面板重建即可"
  [egg_playing]="✿ 東方萃夢想！Bad Apple!! 开始播放~ (Ctrl+C 可以切回菜单)"
  [egg_noplayer_nix]="  没有找到播放器，用 nix run 临时拉取 mpv 播放..."
  [egg_noplayer_found]="  找不到任何播放器，视频文件在：%s"
  [egg_install_mpv]="  安装 mpv 后输入 touhou 就能播了"
)

# _t <键> [printf参数...]：翻译（找不到键或键为空就原样返回）
_t() {
  local key="$1"; shift
  [[ -z "$key" ]] && return 0
  local fmt
  if [[ "$LANG_UI" == "zh" ]]; then
    fmt="${L10N_ZH[$key]:-}"
    [[ -z "$fmt" ]] && fmt="${L10N_EN[$key]:-$key}"
  else
    fmt="${L10N_EN[$key]:-$key}"
  fi
  printf "$fmt" "$@"
}

# ============================================================================
# 通用工具：输出（优先 /dev/tty，兼容 curl|bash；无 tty 回退 stdout）
# ============================================================================
_tty_out() {
  if { printf '%b' "$*" > /dev/tty; } 2>/dev/null; then :; else printf '%b' "$*"; fi
}
say()    { _tty_out "$(_t "$@")\n"; }
info()   { _tty_out "${C_CYAN}[*]${C_RESET} $(_t "$@")\n"; }
ok()     { _tty_out "${C_GREEN}[✓]${C_RESET} $(_t "$@")\n"; }
warn()   { _tty_out "${C_YELLOW}[!]${C_RESET} $(_t "$@")\n"; }
die()    { _tty_out "${C_RED}[✗]${C_RESET} $(_t "$@")\n"; exit 1; }
prompt() { _tty_out "$(_t "$@")"; }

# ASCII 字符画
banner() {
  say "${C_CYAN}"
  say '##     ## ######## ##    ## #### ##     ##  #######   ######          ######## ########  ######'
  say '##     ##    ##    ###   ##  ##   ##   ##  ##     ## ##    ##          ##    ## ##    ## ##    ##'
  say '##     ##    ##    ####  ##  ##    ## ##   ##     ## ##          ##    ## ##    ## ##    ##'
  say '##     ##    ##    ## ## ##  ##     ###    ##     ##  ######          ######## ######## ##    ##'
  say '##     ##    ##    ##  ####  ##    ## ##   ##     ##       ##          ##       ##   ##  ##    ##'
  say '##     ##    ##    ##   ###  ##   ##   ##  ##     ## ##    ##          ##       ##  ##   ##    ##'
  say ' #######     ##    ##    ## #### ##     ##  #######   ###### ######## ##       ##   ##   ######'
  say "${C_RESET}"
}

# 菜单：单选 / 多选
PICKED=""
opt_label() {
  local name="$1"
  local t
  t="$(_t "opt_${name}")"
  if [[ "$t" != "opt_${name}" ]]; then
    printf '%s (%s)' "$t" "$name"
  else
    printf '%s' "$name"
  fi
}

label_list() {
  local -a out=()
  local w
  for w in $1; do
    [[ -n "$w" ]] || continue
    out+=("$(opt_label "$w")")
  done
  printf '%s' "${out[*]}"
}

pick_one() {
  local title; title="$(_t "$1")"; shift
  local -a names=("$@")
  local n=${#names[@]}
  PICKED=""
  while :; do
    say ""
    say "${C_BOLD}== $title ==${C_RESET}"
    local i
    for ((i=0;i<n;i++)); do
      printf '  %2d) %s\n' $((i+1)) "$(opt_label "${names[$i]}")" > /dev/tty 2>/dev/null || true
    done
    prompt menu_choose "$n"
    local choice=""
    read -r choice < /dev/tty || choice="1"
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    [[ -z "$choice" ]] && choice="1"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      PICKED="${names[$((choice-1))]}"
      return 0
    fi
  done
}

PICKED_MULTI=""
pick_multi() {
  local title="$(_t "$1")"
  local default_on="$2"; shift 2
  local -a names=("$@")
  local -A on=()
  local d
  for d in $default_on; do on[$d]=1; done
  local n=${#names[@]}
  say ""
  say "${C_BOLD}== $title $(_t multi_suffix) ==${C_RESET}"
  while :; do
    local i
    for ((i=0;i<n;i++)); do
      local mark="[ ]"
      [[ ${on[${names[$i]}]:-0} -eq 1 ]] && mark="[x]"
      printf '  %2d) %s %s\n' $((i+1)) "$mark" "$(opt_label "${names[$i]}")" > /dev/tty 2>/dev/null || true
    done
    prompt multi_prompt
    local choice=""
    read -r choice < /dev/tty || choice=""
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    [[ -z "$choice" ]] && break
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      local k="${names[$((choice-1))]}"
      on[$k]=$(( 1 - ${on[$k]:-0} ))
    fi
  done
  local -a out=()
  for ((i=0;i<n;i++)); do
    [[ ${on[${names[$i]}]:-0} -eq 1 ]] && out+=("${names[$i]}")
  done
  PICKED_MULTI="${out[*]}"
}

# sed 辅助：注释/取消注释 imports（不能带行尾锚点 $：import 行后常跟 #注释）
comment_import() {
  local cfg="$1" pat="$2"
  sed -i -E "s|^([[:space:]]*)#?(\./modules/${pat}[^#]*)|\1#\2|" "$cfg"
}
uncomment_import() {
  local cfg="$1" pat="$2"
  sed -i -E "s|^([[:space:]]*)#(\./modules/${pat}[^#]*)|\1\2|" "$cfg"
}

# ============================================================================
# 彩蛋（touhou → Bad Apple!!）
# ============================================================================
find_badapple() {
  local d
  for d in "${SCRIPT_SRC:-}" "$INSTALL_DIR"; do
    if [[ -n "$d" && -f "$d/media/badapple.mp4" ]]; then
      echo "$d/media/badapple.mp4"
      return 0
    fi
  done
  return 1
}

play_badapple() {
  local mp4
  mp4="$(find_badapple)" || {
    say egg_notfound1
    say egg_notfound2
    say egg_notfound3
    return 1
  }
  say egg_playing
  if command -v mpv >/dev/null 2>&1; then
    mpv --really-quiet "$mp4" >/dev/null 2>&1 &
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -autoexit -loglevel quiet "$mp4" >/dev/null 2>&1 &
  elif command -v vlc >/dev/null 2>&1; then
    vlc --play-and-exit "$mp4" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$mp4" >/dev/null 2>&1 &
  elif command -v nix >/dev/null 2>&1; then
    say egg_noplayer_nix
    nix run nixpkgs#mpv -- "$mp4" >/dev/null 2>&1 &
  else
    say egg_noplayer_found "$mp4"
    say egg_install_mpv
  fi
  sleep 1
}

is_touhou() {
  local input
  input="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:] ')"
  [[ "$input" == "touhou" ]]
}

# ============================================================================
# 环境判定：live / 已装系统（与旧版同判据）
# ============================================================================
is_live_env() {
  if [[ -L /nix/var/nix/profiles/system ]] && [[ -f /etc/nixos/hardware-configuration.nix ]]; then
    return 1
  fi
  if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == "overlay" ]]; then
    return 0
  fi
  if id nixos >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -L /nix/var/nix/profiles/system ]] && [[ ! -f /etc/nixos/hardware-configuration.nix ]]; then
    return 0
  fi
  return 1
}

# ============================================================================
# 配置源码获取（安装/修复共用）
#   clone_config <目标目录>：优先 git clone；NO_APPLE=1 时稀疏检出跳过 media/
#   防挂起：git 低速 30 秒中止；git/curl 读取环境里的代理变量
# ============================================================================
clone_config() {
  local dest="$1"
  export GIT_TERMINAL_PROMPT=0
  local slow=(--config http.lowSpeedLimit=1000 --config http.lowSpeedTime=30)
  local proxy=()
  local _proxy="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
  if [[ -n "$_proxy" ]]; then
    proxy=(-c "http.proxy=$_proxy" -c "https.proxy=$_proxy")
  fi
  if [[ "${NO_APPLE:-0}" == "1" ]] && git --version >/dev/null 2>&1; then
    if git clone --depth 1 --filter=blob:none --sparse "${proxy[@]}" "${slow[@]}" "$GIT_URL" "$dest" >/dev/null 2>&1 \
      && git -C "$dest" sparse-checkout set --no-cone '/*' '!/media/' >/dev/null 2>&1; then
      return 0
    fi
    rm -rf "$dest"    # 稀疏检出失败 → 回退普通克隆（部署时再排除 mp4）
  fi
  git clone --depth 1 "${proxy[@]}" "${slow[@]}" "$GIT_URL" "$dest" >/dev/null 2>&1
}

# 完整仓库校验（拉取/复用前确认不缺关键文件）
repo_complete() {
  local d="$1"
  [[ -d "$d" && -f "$d/flake.nix" && -f "$d/install.sh" && -f "$d/modules/system/webui.nix" ]]
}

# ============================================================================
# 模块选择逻辑（写 configuration.nix / home-manager.nix / 状态文件）
# ============================================================================
apply_selection() {
  local CFG="$TARGET_DIR/configuration.nix"
  [[ -f "$CFG" ]] || die nofile_cfg "$CFG"
  info apply_write "$CFG"

  # 兜底默认值（非交互路径：如用环境变量预设 DESKTOP 直接安装时）
  DESKTOP="${DESKTOP:-xfce}"
  BOOT="${BOOT:-grub-uefi}"
  GRUB_THEME="${GRUB_THEME:-no}"
  GRUB_DEVICE="${GRUB_DEVICE:-}"
  LOCALE="${LOCALE:-en_US}"
  INPUT="${INPUT:-ibus}"
  MIRROR="${MIRROR:-ustc}"
  USERSHELL="${USERSHELL:-zsh}"
  SYSTEM_MODULES="${SYSTEM_MODULES:-auto-update clean nix-command zram fonts}"
  ADVANCED="${ADVANCED:-}"

  # 桌面环境（单选）
  comment_import "$CFG" "desktop/"
  uncomment_import "$CFG" "desktop/${DESKTOP}.nix"

  # 引导（单选：grub-uefi / grub-bios / systemd-boot；GRUB 时按 GRUB_THEME 决定主题）
  comment_import "$CFG" "boot/"
  case "$BOOT" in
    systemd-boot) uncomment_import "$CFG" "boot/systemd-boot.nix" ;;
    grub-bios)    uncomment_import "$CFG" "boot/grub-bios.nix" ;;
    *)            uncomment_import "$CFG" "boot/grub.nix" ;;
  esac
  if [[ "${GRUB_THEME:-no}" == "yes" ]]; then
    uncomment_import "$CFG" "boot/grub-theme.nix"
  fi
  write_grub_device

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

  # 系统模块（多选；Web 管理面板 webui.nix / ut 命令 ut.nix 为系统内置，
  # 不在选择范围内——旧配置若把它们注释了，这里也强制打开）
  local m
  for m in auto-update clean nix-command zram fonts nopwdtodesktop vm-debug; do
    if [[ " $SYSTEM_MODULES " == *" $m "* ]]; then
      uncomment_import "$CFG" "system/${m}.nix"
    else
      comment_import "$CFG" "system/${m}.nix"
    fi
  done
  uncomment_import "$CFG" "system/webui.nix"
  uncomment_import "$CFG" "system/ut.nix"

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
  ok apply_done
}

# GRUB(BIOS) 目标磁盘（机器本地文件 host/grub-device.nix）
write_grub_device() {
  local f="$TARGET_DIR/host/grub-device.nix"
  mkdir -p "$TARGET_DIR/host"
  if [[ "$BOOT" == "grub-bios" && -n "${GRUB_DEVICE:-}" ]]; then
    cat > "$f" <<EOF
# UTNixOS_Pro - GRUB(BIOS) 引导设备（机器本地文件，自动维护）
# 警告：此文件由安装脚本 / Web 管理面板自动写入，请勿手动编辑。
{ ... }: {
  boot.loader.grub.device = "${GRUB_DEVICE}";
}
EOF
  else
    cat > "$f" <<'EOF'
# UTNixOS_Pro - GRUB(BIOS) 引导设备（机器本地文件，自动维护）
# 当前为空模块：表示未使用 GRUB(BIOS)，不产生任何配置。
{ ... }: { }
EOF
  fi
}

# 选择状态持久化（与 Web 面板共用 .utnixos-pro-selection）
# 注意：Web 管理面板（webui）是系统内置，不再出现在 SYSTEM_MODULES 里。
save_state() {
  local st="$TARGET_DIR/$STATE_FILE"
  cat > "$st" <<EOF
# UTNixOS_Pro module selection state (generated by install.sh / Web panel; edit then re-apply)
STATE_VERSION=3
DESKTOP=$DESKTOP
BOOT=$BOOT
GRUB_THEME=${GRUB_THEME:-no}
GRUB_DEVICE=${GRUB_DEVICE:-}
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
    # 逐行解析，不能用 . (source)！多值行被 source 时会把后面的词当命令执行。
    local k v line
    while IFS= read -r line; do
      [[ "$line" == \#* || -z "$line" ]] && continue
      k="${line%%=*}"
      v="${line#*=}"
      case "$k" in
        DESKTOP)         DESKTOP="$v" ;;
        BOOT)            BOOT="$v" ;;
        GRUB_THEME)      GRUB_THEME="$v" ;;
        GRUB_DEVICE)     GRUB_DEVICE="$v" ;;
        LOCALE)          LOCALE="$v" ;;
        INPUT)           INPUT="$v" ;;
        MIRROR)          MIRROR="$v" ;;
        USERSHELL)       USERSHELL="$v" ;;
        SYSTEM_MODULES)  SYSTEM_MODULES="$v" ;;
        ADVANCED)        ADVANCED="$v" ;;
      esac
    done < "$st"
    # 旧版本状态兼容：grub-theme/grub-notheme → grub-uefi + 主题开关
    case "${BOOT:-}" in
      grub-theme)   BOOT="grub-uefi"; GRUB_THEME=yes ;;
      grub-notheme) BOOT="grub-uefi"; GRUB_THEME=no ;;
    esac
    GRUB_THEME="${GRUB_THEME:-no}"
    GRUB_DEVICE="${GRUB_DEVICE:-}"
    # 清洗：webui 已内置，从 SYSTEM_MODULES 中去掉（旧状态里可能有）
    local cleaned=""
    local w
    for w in ${SYSTEM_MODULES:-}; do
      [[ "$w" == "webui" ]] && continue
      cleaned="${cleaned:+$cleaned }$w"
    done
    SYSTEM_MODULES="$cleaned"
    ok state_restored
  fi
}

# GRUB(BIOS) 目标磁盘：列出检测到的磁盘 + 手动输入（回车默认 /dev/sda）
pick_grub_device() {
  local detected=""
  if command -v lsblk >/dev/null 2>&1; then
    detected="$(lsblk -dno NAME,SIZE,MODEL -e 7,11 2>/dev/null || true)"
  fi
  if [[ -n "$detected" ]]; then
    info t_grub_disk_list
    local d
    while IFS= read -r d; do
      [[ -n "$d" ]] && say "    /dev/$d"
    done <<< "$detected"
  fi
  prompt t_grub_disk_manual
  read -r GRUB_DEVICE < /dev/tty || GRUB_DEVICE="/dev/sda"
  GRUB_DEVICE="$(printf '%s' "$GRUB_DEVICE" | tr -d '[:space:]')"
  [[ -n "$GRUB_DEVICE" ]] || GRUB_DEVICE="/dev/sda"
  if [[ "$GRUB_DEVICE" != /dev/* ]]; then
    warn t_grub_disk_invalid "$GRUB_DEVICE"
    GRUB_DEVICE="/dev/sda"
  fi
  if [[ -e "$GRUB_DEVICE" ]]; then
    ok t_grub_disk_set "$GRUB_DEVICE"
  else
    warn t_grub_disk_missing "$GRUB_DEVICE"
  fi
}

# 交互式选择全部模块
run_menu() {
  say ""
  say "${C_BOLD}$(_t menu_intro)${C_RESET}"
  say "${C_YELLOW}$(_t menu_hint)${C_RESET}"

  pick_one t_boot grub-uefi grub-bios systemd-boot
  BOOT="$PICKED"

  GRUB_THEME="no"
  GRUB_DEVICE=""
  if [[ "$BOOT" == grub-* ]]; then
    prompt t_grub_theme_q
    local ans=""
    read -r ans < /dev/tty || ans="y"
    [[ "$ans" =~ ^[Nn]$ ]] || GRUB_THEME="yes"
    if [[ "$BOOT" == grub-bios ]]; then
      pick_grub_device
    fi
  fi

  pick_one t_desktop xfce gnome kde lxqt hyprland cosmic
  DESKTOP="$PICKED"

  pick_one t_locale en_US zh_CN
  LOCALE="$PICKED"

  pick_one t_input ibus fcitx5
  INPUT="$PICKED"

  pick_one t_mirror ustc tuna nju sjtu
  MIRROR="$PICKED"

  pick_one t_shell zsh bash fish
  USERSHELL="$PICKED"

  # Web 面板（webui）为系统内置，不在此多选列表
  pick_multi t_sysmods "auto-update clean nix-command zram fonts" \
    auto-update clean nix-command zram fonts nopwdtodesktop vm-debug
  SYSTEM_MODULES="$PICKED_MULTI"

  pick_multi t_advmods "" secrets impermanence backup security
  ADVANCED="$PICKED_MULTI"
}

# 展示当前选择
show_selection() {
  say ""
  say "${C_BOLD}$(_t cur_selection)${C_RESET}"
  if [[ -n "${USRNAME:-}" ]]; then
    say "  $(_t lab_user) : ${USRNAME}"
  fi
  say "  $(_t lab_desktop) : $(opt_label "${DESKTOP:-xfce}")"
  say "  $(_t lab_boot) : $(opt_label "${BOOT:-grub-uefi}")"
  if [[ "${BOOT:-grub-uefi}" == grub-* ]]; then
    say "    $(_t lab_grub_theme) : ${GRUB_THEME:-no}"
  fi
  if [[ "${BOOT:-grub-uefi}" == grub-bios ]]; then
    say "    $(_t lab_grub_device) : ${GRUB_DEVICE:-/dev/sda}"
  fi
  say "  $(_t lab_locale) : $(opt_label "${LOCALE:-en_US}")"
  say "  $(_t lab_input) : $(opt_label "${INPUT:-ibus}")"
  say "  $(_t lab_mirror) : $(opt_label "${MIRROR:-ustc}")"
  say "  $(_t lab_shell) : $(opt_label "${USERSHELL:-zsh}")"
  say "  $(_t lab_sysmods) : $(label_list "${SYSTEM_MODULES:-auto-update clean nix-command zram fonts}")"
  if [[ -n "${ADVANCED:-}" ]]; then
    say "  $(_t lab_advmods) : $(label_list "$ADVANCED")"
  else
    say "  $(_t lab_advmods) : $(_t val_none)"
  fi
  say ""
}

# ============================================================================
# 安装账号：自定义用户名 / 初始密码（写回配置一律用 sed）
#
#   ask_identity  ：安装向导里询问用户名与密码（回车用默认 reimilia / 123456；
#                   支持环境变量 UTNIXOS_PRO_USER / UTNIXOS_PRO_PASS 预设，跳过询问）
#   apply_identity：把账号写进已部署到 $TARGET_DIR 的配置：
#                     modules/users/reimilia.nix  账号名 + description + 密码哈希
#                     flake.nix                   home-manager.users.<名>
#                     home/home-manager.nix       home.username / homeDirectory
#                     modules/system/nopwdtodesktop.nix  免密自动登录用户名
# ============================================================================
tty_nl() { printf '\n' > /dev/tty 2>/dev/null || printf '\n'; }

# 生成 sha512crypt 哈希（openssl → mkpasswd → python3 逐级兜底）
pass_hash() {
  local p="$1" salt=""
  salt="$(head -c 48 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9./' | head -c 16)"
  [[ -n "$salt" ]] || salt="utnixosprosalt"
  if command -v openssl >/dev/null 2>&1; then
    local h
    h="$(openssl passwd -6 -salt "$salt" "$p" 2>/dev/null)" || h=""
    if [[ -n "$h" ]]; then printf '%s' "$h"; return 0; fi
  fi
  if command -v mkpasswd >/dev/null 2>&1; then
    local h
    h="$(mkpasswd -m sha-512 -S "$salt" "$p" 2>/dev/null)" || h=""
    if [[ -n "$h" ]]; then printf '%s' "$h"; return 0; fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    local h
    h="$(P="$p" S="$salt" python3 -c 'import crypt,os;print(crypt.crypt(os.environ["P"], "$6$"+os.environ["S"]+"$"))' 2>/dev/null)" || h=""
    if [[ -n "$h" ]]; then printf '%s' "$h"; return 0; fi
  fi
  return 1
}

ask_identity() {
  USRNAME=""
  PASSWD=""
  if [[ -n "${UTNIXOS_PRO_USER:-}" ]]; then USRNAME="$UTNIXOS_PRO_USER"; fi
  if [[ -n "${UTNIXOS_PRO_PASS:-}" ]]; then PASSWD="$UTNIXOS_PRO_PASS"; fi

  # 用户名（回车 = 默认）
  if [[ -z "$USRNAME" ]]; then
    while :; do
      prompt ident_prompt_user "$DEFAULT_USER"
      local ans=""
      read -r ans < /dev/tty || ans="$DEFAULT_USER"
      ans="${ans:-$DEFAULT_USER}"
      if [[ "$ans" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        USRNAME="$ans"
        break
      fi
      warn ident_user_invalid "$ans"
    done
  fi

  # 密码（输入不回显；回车 = 默认；自定义需二次确认）
  if [[ -z "$PASSWD" ]]; then
    while :; do
      prompt ident_prompt_pass "$USRNAME" "$DEFAULT_PASS"
      local p1="" p2=""
      read -rsp '' p1 < /dev/tty || p1=""
      tty_nl
      [[ -n "$p1" ]] || p1="$DEFAULT_PASS"
      if [[ "$p1" == "$DEFAULT_PASS" ]]; then
        PASSWD="$p1"
        break
      fi
      if (( ${#p1} < 6 )); then
        warn ident_pass_short
        continue
      fi
      prompt ident_pass_confirm
      read -rsp '' p2 < /dev/tty || p2=""
      tty_nl
      if [[ "$p1" == "$p2" ]]; then
        PASSWD="$p1"
        break
      fi
      warn ident_pass_mismatch
    done
  fi
  export USRNAME PASSWD
}

apply_identity() {
  local dir="${1:-$TARGET_DIR}"
  USRNAME="${USRNAME:-$DEFAULT_USER}"
  PASSWD="${PASSWD:-$DEFAULT_PASS}"
  # 全默认账号：仓库自带配置（reimilia / 123456 哈希）就是对的，无需改动
  if [[ "$USRNAME" == "$DEFAULT_USER" && "$PASSWD" == "$DEFAULT_PASS" ]]; then
    return 0
  fi

  local usersf="$dir/modules/users/reimilia.nix"
  local flakef="$dir/flake.nix"
  local hmf="$dir/home/home-manager.nix"
  local nopw="$dir/modules/system/nopwdtodesktop.nix"

  # 1) 自定义用户名：sed 同步账号名出现处
  if [[ "$USRNAME" != "$DEFAULT_USER" ]]; then
    if [[ -f "$usersf" ]]; then
      sed -i -E "s|users\\.users\\.${DEFAULT_USER}|users.users.${USRNAME}|g" "$usersf"
      sed -i -E "s|description = \"Reimilia\";|description = \"${USRNAME}\";|" "$usersf"
    fi
    if [[ -f "$flakef" ]]; then
      sed -i -E "s|home-manager\\.users\\.${DEFAULT_USER}|home-manager.users.${USRNAME}|g" "$flakef"
    fi
    if [[ -f "$hmf" ]]; then
      sed -i -E "s|home\\.username = \"${DEFAULT_USER}\";|home.username = \"${USRNAME}\";|" "$hmf"
      sed -i -E "s|home\\.homeDirectory = \"/home/${DEFAULT_USER}\";|home.homeDirectory = \"/home/${USRNAME}\";|" "$hmf"
    fi
    if [[ -f "$nopw" ]]; then
      sed -i -E "s|user = \"${DEFAULT_USER}\";|user = \"${USRNAME}\";|" "$nopw"
    fi
  fi

  # 2) 自定义密码：sed 替换为新的 sha512 哈希（默认 123456 时仓库哈希已正确）
  if [[ "$PASSWD" != "$DEFAULT_PASS" ]]; then
    local hash=""
    if ! hash="$(pass_hash "$PASSWD")" || [[ -z "$hash" ]]; then
      die ident_hash_fail
    fi
    if [[ -f "$usersf" ]]; then
      sed -i -E "s|^([[:space:]]*)initialHashedPassword = .*;|\\1initialHashedPassword = \"${hash}\";|" "$usersf"
    fi
  fi

  # 3) 账号是「机器本地定制」：打上 git skip-worktree，Web 面板「更新配置」时
  #    不会被 git reset 覆盖回默认 reimilia（与 hardware-configuration.nix 同理）
  if [[ -d "$dir/.git" ]] && command -v git >/dev/null 2>&1; then
    git -C "$dir" update-index --skip-worktree \
      modules/users/reimilia.nix flake.nix home/home-manager.nix \
      modules/system/nopwdtodesktop.nix 2>/dev/null || true
  fi

  ok ident_applied "$USRNAME"
}

# ============================================================================
# 全新安装（在 NixOS live 环境运行）
# ============================================================================
cmd_install() {
  banner
  [[ $EUID -eq 0 || -n "${UTNIXOS_PRO_TEST:-}" ]] || die inst_root

  TARGET_DIR="$MOUNT_ROOT/etc/nixos"

  say ""
  info inst_check_mount
  mountpoint -q "$MOUNT_ROOT" || die inst_mount_missing "$MOUNT_ROOT" "$MOUNT_ROOT"
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
  # 自定义用户名 / 初始密码（回车=默认 reimilia / 123456）
  ask_identity
  show_selection

  prompt inst_confirm
  local ans=""
  read -r ans < /dev/tty || ans="n"
  [[ "$ans" =~ ^[Yy]$ ]] || die inst_cancel

  # 获取配置源码：优先复用本地完整仓库（SCRIPT_SRC，带 .git），否则自己拉取
  # 注意：SCRIPT_SRC 若等于 INSTALL_DIR，那是本地旧配置，不能复用，必须拉最新的。
  info inst_prep
  local src=""
  if repo_complete "${SCRIPT_SRC:-}" \
     && [[ -d "${SCRIPT_SRC:-}/.git" && "${SCRIPT_SRC:-}" != "$INSTALL_DIR" ]]; then
    src="$SCRIPT_SRC"
    ok inst_reuse "$src"
  else
    src="$(mktemp -d)"
    info inst_fetch_doing
    local _proxy="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
    local curl_proxy=()
    [[ -n "$_proxy" ]] && curl_proxy=(-x "$_proxy")
    if command -v git >/dev/null 2>&1; then
      clone_config "$src" || true
    fi
    if ! repo_complete "$src"; then
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "${curl_proxy[@]}" --connect-timeout 15 --max-time 600 "$TARBALL_URL" \
             | tar -xz -C "$src" --strip-components=1; then
          die inst_dl_fail
        fi
      fi
    fi
    # 完整性校验：拉取不完整（缺 flake.nix 等）就中止
    if ! repo_complete "$src"; then
      die inst_clone_fail
    fi
    [[ "${NO_APPLE:-0}" == "1" ]] && rm -f "$src/media/badapple.mp4"
  fi

  info inst_gen_hw
  nixos-generate-config --root "$MOUNT_ROOT"

  info inst_deploy "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  # 复制全部文件（保留 .git 以便 Web 面板「更新配置」同步），
  # 但不覆盖刚生成的 hardware-configuration.nix
  local rsync_opts=(-a --exclude='hardware-configuration.nix')
  [[ "${NO_APPLE:-0}" == "1" ]] && rsync_opts+=(--exclude='media/badapple.mp4')
  rsync "${rsync_opts[@]}" "$src/" "$TARGET_DIR/"
  chmod +x "$TARGET_DIR/install.sh" 2>/dev/null || true   # 可执行位保险
  if [[ -d "$TARGET_DIR/.git" ]]; then
    git -C "$TARGET_DIR" update-index --skip-worktree hardware-configuration.nix 2>/dev/null || true
  fi

  # 应用选择（webui/ut 内置强制打开）
  apply_selection

  # 应用自定义用户名 / 密码（sed 写回 users 模块 / flake / home-manager / 免密登录）
  apply_identity

  say ""
  info inst_start

  # nixos-install 参数：flake + 镜像 substituters；有代理变量则一并传给 nix
  local -a inst_opts=(
    --flake "$TARGET_DIR#reimilia"
    --option substituters "${MIRROR_URLS[$MIRROR]:-${MIRROR_URLS[ustc]}}"
  )
  local _proxy="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
  if [[ -n "$_proxy" ]]; then
    info inst_proxy "$_proxy"
    inst_opts+=(--option proxy "$_proxy")
  fi
  nixos-install "${inst_opts[@]}"

  say ""
  ok "${C_BOLD}$(_t inst_done)${C_RESET}"
  say inst_step1
  if [[ "${USRNAME:-}" == "$DEFAULT_USER" && "${PASSWD:-}" == "$DEFAULT_PASS" ]]; then
    say inst_step2 "$DEFAULT_USER" "$DEFAULT_PASS"
  else
    say inst_step2_custom "${USRNAME:-$DEFAULT_USER}"
  fi
  say inst_step3
}

# ============================================================================
# 修复配置：/etc/nixos 损坏时重建（保留机器专属文件）
#   - hardware-configuration.nix / host/packages.nix / host/grub-device.nix
#   - .utnixos-pro-selection（会重新应用回 configuration.nix）
#   安全设计：先全量备份到 /etc/nixos.repair-<时间戳>；失败自动回滚，绝不先删。
# ============================================================================
cmd_repair() {
  banner
  say ""
  say "${C_BOLD}$(_t repair_heading)${C_RESET}"
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
    # 安装时自定义过的用户名/密码也是机器专属：一并备份（默认 reimilia 时内容等同仓库）
    [[ -f "$mf/users-module.nix" ]]   || cp -f "$mdir/modules/users/reimilia.nix" "$mf/users-module.nix" 2>/dev/null || true
    [[ -f "$mf/flake-nix" ]]          || cp -f "$mdir/flake.nix" "$mf/flake-nix" 2>/dev/null || true
    [[ -f "$mf/hm-nix" ]]             || cp -f "$mdir/home/home-manager.nix" "$mf/hm-nix" 2>/dev/null || true
    [[ -f "$mf/nopwd-nix" ]]          || cp -f "$mdir/modules/system/nopwdtodesktop.nix" "$mf/nopwd-nix" 2>/dev/null || true
  done

  # ---------- 3. 获取最新源码：优先复用引导/克隆来的完整仓库，否则从 GitHub 拉取 ----------
  # SCRIPT_SRC == TARGET_DIR（从 /etc/nixos/install.sh 直接跑 repair）说明本地配置
  # 被当成源码——可能是旧代码/损坏代码，绝不能复用，必须拉最新。
  local src=""
  if repo_complete "${SCRIPT_SRC:-}" && [[ "${SCRIPT_SRC:-}" != "$TARGET_DIR" ]]; then
    src="$SCRIPT_SRC"
    ok repair_reuse "$src"
  else
    if [[ "${SCRIPT_SRC:-}" == "$TARGET_DIR" ]]; then
      warn repair_local_stale
    fi
    src="$(mktemp -d)"
    info repair_fetch
    local _proxy="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
    local curl_proxy=()
    [[ -n "$_proxy" ]] && curl_proxy=(-x "$_proxy")
    if command -v git >/dev/null 2>&1; then
      clone_config "$src" || true
    fi
    if ! repo_complete "$src" && command -v curl >/dev/null 2>&1; then
      curl -fsSL "${curl_proxy[@]}" --connect-timeout 15 --max-time 600 "$TARBALL_URL" \
        | tar -xz -C "$src" --strip-components=1 || true
    fi
    # 完整性校验：拉取不完整就中止，绝不碰现有配置
    if ! repo_complete "$src"; then
      die repair_fetch_fail
    fi
    [[ "${NO_APPLE:-0}" == "1" ]] && rm -f "$src/media/badapple.mp4"
  fi

  # ---------- 4. 重建 /etc/nixos：完整源码 + 恢复机器文件（失败自动回滚） ----------
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  if ! cp -a "$src/." "$TARGET_DIR/"; then
    rm -rf "$TARGET_DIR"
    [[ "$have_bk" == "1" ]] && cp -a "$bk" "$TARGET_DIR" 2>/dev/null
    die repair_swap_fail
  fi
  chmod +x "$TARGET_DIR/install.sh" 2>/dev/null || true   # 可执行位保险
  mkdir -p "$TARGET_DIR/host" "$TARGET_DIR/modules/users" "$TARGET_DIR/modules/system" "$TARGET_DIR/home"
  cp -f "$mf/hardware-configuration.nix" "$TARGET_DIR/" 2>/dev/null || true
  cp -f "$mf/packages.nix" "$TARGET_DIR/host/" 2>/dev/null || true
  cp -f "$mf/grub-device.nix" "$TARGET_DIR/host/" 2>/dev/null || true
  cp -f "$mf/.utnixos-pro-selection" "$TARGET_DIR/" 2>/dev/null || true
  # 恢复机器自定义账号（安装了自定义用户名/密码的机器；默认内容=仓库内容，恢复无害）
  cp -f "$mf/users-module.nix" "$TARGET_DIR/modules/users/reimilia.nix" 2>/dev/null || true
  cp -f "$mf/flake-nix"        "$TARGET_DIR/flake.nix" 2>/dev/null || true
  cp -f "$mf/hm-nix"           "$TARGET_DIR/home/home-manager.nix" 2>/dev/null || true
  cp -f "$mf/nopwd-nix"        "$TARGET_DIR/modules/system/nopwdtodesktop.nix" 2>/dev/null || true
  rm -rf "$mf"

  # 若账号确实被自定义过（不再等于默认 reimilia），重新打 skip-worktree，
  # 避免之后的 Web 面板「更新配置」（git reset）把账号还原成仓库默认
  if ! grep -q 'users\.users\.reimilia = {' "$TARGET_DIR/modules/users/reimilia.nix" 2>/dev/null; then
    if [[ -d "$TARGET_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
      git -C "$TARGET_DIR" update-index --skip-worktree \
        modules/users/reimilia.nix flake.nix home/home-manager.nix \
        modules/system/nopwdtodesktop.nix 2>/dev/null || true
    fi
  fi

  # ---------- 5. 硬件配置缺失时兜底生成（基于当前运行的系统） ----------
  if [[ ! -f "$TARGET_DIR/hardware-configuration.nix" ]]; then
    warn repair_no_hw
    if command -v nixos-generate-config >/dev/null 2>&1; then
      nixos-generate-config || warn repair_no_hw_fail
    fi
  fi

  # ---------- 6. 重放模块选择（有状态文件时；webui/ut 内置强制打开） ----------
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
  # 诚实验证（不猜测）：修复后 webui 是内置服务，主动查真实状态
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active utnixos-pro-webui >/dev/null 2>&1; then
      ok repair_webui_active
    else
      warn repair_webui_inactive
    fi
  fi
}

# ============================================================================
# UT紧急回滚（纯操作系统 profile 的 generations，不依赖 /etc/nixos 配置）
# ============================================================================
cmd_rollback() {
  banner
  say ""
  say "${C_BOLD}$(_t roll_heading)${C_RESET}"
  # 允许测试时用 UTNIXOS_PRO_TEST_PROF 覆盖 profile 路径
  local PROF="${UTNIXOS_PRO_TEST_PROF:-/nix/var/nix/profiles/system}"
  [[ -e "$PROF" ]] || die roll_no_profile "$PROF"

  say ""
  say "${C_BOLD}$(_t roll_current_gen)${C_RESET}"
  nix-env --list-generations -p "$PROF" 2>/dev/null || nix profile history --profile "$PROF" 2>/dev/null || die roll_no_read
  say ""
  say roll_current_run "$(readlink -f /run/current-system 2>/dev/null || echo $(_t roll_unknown))"

  prompt roll_prompt
  local gen=""
  read -r gen < /dev/tty || gen=""

  if [[ -z "$gen" ]]; then
    info roll_exec
    nixos-rebuild switch --rollback
  else
    info roll_switch_gen "$gen"
    nix-env --switch-generation "$gen" -p "$PROF"
    info roll_activate
    /run/current-system/bin/switch-to-configuration switch
  fi

  ok roll_done
}

# ============================================================================
# 帮助
# ============================================================================
cmd_help() {
  banner
  say help_usage
  say help_install
  say help_install_cmd
  say help_repair
  say help_rollback
  say ""
  say help_no_apple
  say ""
  say help_ut
  say ""
  say help_curl "$RAW_URL"
  say help_curl_rollback
  say help_curl_rollback_cmd "$RAW_URL"
}

# ============================================================================
# 交互入口菜单（进入脚本时可选：安装 / 修复配置 / UT紧急回滚）
# ============================================================================
cmd_entry() {
  banner

  if is_live_env; then
    say ""
    info entry_hint_live
  else
    say ""
    info entry_hint_installed
    say entry_hint_ut
    say entry_help_hint
  fi

  while :; do
    say ""
    say "${C_BOLD}$(_t entry_welcome)${C_RESET}"
    say entry_opt_install
    say entry_opt_repair
    say entry_opt_rollback
    say entry_opt_quit
    prompt entry_prompt
    local choice=""
    read -r choice < /dev/tty || choice="1"
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    case "$choice" in
      ""|1) cmd_install; return 0 ;;
      2)    cmd_repair;  return 0 ;;
      3)    cmd_rollback; return 0 ;;
      q|Q|0|exit|quit) say ""; return 0 ;;
      *)    warn entry_invalid "$choice" ;;
    esac
  done
}

# ============================================================================
# 命令路由
# ============================================================================
main() {
  # 解析全局参数（可出现在任意位置）
  NO_APPLE="${NO_APPLE:-0}"
  local -a args=()
  local a
  for a in "$@"; do
    case "$a" in
      --no-apple) NO_APPLE=1 ;;
      *) args+=("$a") ;;
    esac
  done
  # 兼容 curl | bash -s -- <mode>：部分 sh 实现把第一个参数放进 $0 而不是 $1
  if [[ "${args[0]:-}" == "" && "$0" =~ ^(install|repair|rollback|--rollback|--repair|help|-h|--help|menu|update|dashboard)$ ]]; then
    args=("$0")
  fi

  local mode="${args[0]:-entry}"
  case "$mode" in
    install|entry|auto)    # auto/无参数：交互入口菜单（旧 dashboard/menu/update 已移除 → Web 面板）
      if [[ "$mode" == "entry" || "$mode" == "auto" ]]; then
        cmd_entry
      else
        cmd_install
      fi
      ;;
    repair|--repair) cmd_repair ;;
    rollback|--rollback|-r) cmd_rollback ;;
    help|-h|--help) cmd_help ;;
    # 旧管理子命令：已由 Web 面板接管，给出明确指引而不是静默消失
    menu|update|dashboard|panel|dash)
      say ""
      warn oldcmd_gone "$mode"
      say ""
      say help_usage
      say help_install_cmd
      say help_repair
      say help_rollback
      say ""
      say help_ut
      ;;
    *) die unknown_arg "$mode" ;;
  esac
}

# 测试钩子：UTNIXOS_PRO_TEST=1 时不会自动执行 main（供测试 source 本文件用）
if [[ -z "${UTNIXOS_PRO_TEST:-}" ]]; then
  main "$@"
fi
