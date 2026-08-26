# UTNixOS_Pro 脚本配置（script/lib/env.sh）
# 被 script/main.sh 自动加载。修改这里的配置会影响所有命令。

# ---------- 仓库与路径 ----------
# 支持环境变量覆盖（fork 或本地测试）：UTNIXOS_PRO_GIT_URL / UTNIXOS_PRO_TARBALL_URL / UTNIXOS_PRO_RAW_URL
GIT_URL="${UTNIXOS_PRO_GIT_URL:-https://github.com/Reimilia617/UTNixOS_Pro.git}"
TARBALL_URL="${UTNIXOS_PRO_TARBALL_URL:-https://github.com/Reimilia617/UTNixOS_Pro/archive/refs/heads/main.tar.gz}"
RAW_URL="${UTNIXOS_PRO_RAW_URL:-https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh}"   # curl|bash 用的单文件地址
INSTALL_DIR="/etc/nixos"          # 已安装系统上的配置目录
MOUNT_ROOT="/mnt"                 # live 环境挂载点
HOSTNAME="reimilia"               # 主机名（默认）
STATE_FILE=".utnixos-pro-selection"   # 选择状态文件（相对配置目录）

# ---------- 镜像源 URL（与 modules/mirrors/*.nix 保持一致）----------
declare -A MIRROR_URLS=(
  [ustc]="https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org/"
  [tuna]="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org/"
  [nju]="https://mirrors.nju.edu.cn/nix-channels/store https://cache.nixos.org/"
)

# ---------- 颜色 ----------
C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
C_CYAN=$'\e[36m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
