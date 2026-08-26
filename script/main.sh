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
    panel|dash|dashboard) cmd_dashboard ;;
    auto)
      # 自动判断：live 环境（$MOUNT_ROOT 有 etc/nixos）→ install；已装系统 → 管理面板
      if [[ -d "$MOUNT_ROOT/etc/nixos" && -f "$MOUNT_ROOT/etc/nixos/hardware-configuration.nix" ]]; then
        cmd_install
      else
        cmd_dashboard
      fi
      ;;
    -h|--help|help)
      banner
      say "用法："
      say "  install.sh                    # 无参数：live环境=安装 / 已装系统=管理面板"
      say "  install.sh install            # 全新安装（NixOS live 环境）"
      say "  install.sh update             # 更新系统（同步最新代码并重建）"
      say "  install.sh menu               # 选择/更换模块（换桌面、Shell 等）"
      say "  install.sh rollback           # 系统回滚（--rollback 同义）"
      say ""
      say "  --no-apple                    附加参数：不下载/不部署 badapple.mp4（彩蛋将不可用）"
      say ""
      say "  ut 命令（安装后系统内置）等价于 sudo install.sh"
      say ""
      say "  curl 方式安装：curl -L ${RAW_URL} | bash"
      say "  curl 方式回滚（本地脚本坏了也能用）："
      say "    curl -L ${RAW_URL} | sudo bash -s -- --rollback"
      ;;
    *) die "未知参数：$mode（可用：install / update / menu / rollback）" ;;
  esac
}

# 测试钩子：设置 UTNIXOS_PRO_TEST=1 时不会自动执行 main（供测试脚本 source 本文件用）
if [[ -z "${UTNIXOS_PRO_TEST:-}" ]]; then
  main "$@"
fi
