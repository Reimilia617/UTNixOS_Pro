# UTNixOS_Pro 脚本主程序（script/main.sh）
#
# 模块化设计（与 NixOS 的 modules/ 同理）：
#   - script/lib/*.sh          基础设施：env(配置) / util(输出·菜单·sed) / selection(模块选择)
#   - script/commands/*.sh     命令：install / update / menu / rollback / dashboard
#   - 新增命令 = 往 commands/ 丢一个 .sh 文件（定义 cmd_xxx 函数），自动加载
#
# 本文件：加载全部模块 → 解析参数 → 路由到对应命令。
# 由 install.sh（引导器）source 进来，也可单独运行：bash script/main.sh [参数]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 按字母序加载基础设施模块
for _lib in "$DIR"/lib/*.sh; do
  # shellcheck disable=SC1090
  source "$_lib"
done

# 按字母序加载命令模块（新命令丢进 commands/ 即可）
for _cmd in "$DIR"/commands/*.sh; do
  # shellcheck disable=SC1090
  source "$_cmd"
done

# ---------- live 环境判定 ----------
# 注意：不能用「/etc/nixos 是否存在」判断——NixOS live ISO 上同样有 /etc/nixos，
# 也不能用「nixos-install 在 PATH」判断——已装系统的默认 systemPackages 也带它。
# 可靠判据（按优先级）：
#   1) 已装系统硬标志：/nix/var/nix/profiles/system 系统 profile 符号链接 存在
#      且 /etc/nixos/hardware-configuration.nix 存在（本项目安装时生成并保留）
#   2) live 硬标志：根文件系统是 overlay（NixOS live ISO 的 root = squashfs+overlay，
#      普通安装是 ext4/btrfs 等）
#   3) live 硬标志：标准安装 ISO 的默认用户 nixos 存在
#   4) 兜底：既无系统 profile 又无 /etc/nixos 硬件配置 → 按 live 处理（进安装向导
#      比进一个什么都干不了的面板更合适）
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

# ---------- 命令路由 ----------
main() {
  # 解析全局参数（可以出现在任意位置）
  NO_APPLE="${NO_APPLE:-0}"
  local -a args=()
  local a
  for a in "$@"; do
    case "$a" in
      --no-apple) NO_APPLE=1 ;;
      *) args+=("$a") ;;
    esac
  done

  local mode="${args[0]:-auto}"
  case "$mode" in
    install)  cmd_install ;;
    update)   cmd_update ;;
    menu)     cmd_menu ;;
    rollback|--rollback|-r) cmd_rollback ;;
    repair|--repair) cmd_repair ;;
    panel|dash|dashboard) cmd_dashboard ;;
    auto)
      # 自动判断：
      #   - live/安装器环境（无 /etc/nixos 且存在 nixos 用户）→ 安装部署界面
      #   - 已装系统上又挂载了全新 /mnt 并已生成硬件配置 → 安装部署界面（重装）
      #   - 其他（已装系统）→ 管理面板
      if is_live_env \
         || [[ -d "$MOUNT_ROOT/etc/nixos" && -f "$MOUNT_ROOT/etc/nixos/hardware-configuration.nix" ]]; then
        cmd_install
      else
        cmd_dashboard
      fi
      ;;
    -h|--help|help)
      banner
      say help_usage
      say help_install
      say help_install_cmd
      say help_update
      say help_menu
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
      ;;
    *) die unknown_arg "$mode" ;;
  esac
}

# 测试钩子：设置 UTNIXOS_PRO_TEST=1 时不会自动执行 main（供测试脚本 source 本文件用）
if [[ -z "${UTNIXOS_PRO_TEST:-}" ]]; then
  main "$@"
fi
