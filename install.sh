#!/usr/bin/env bash
# ============================================================================
#  UTNixOS_Pro - 管理脚本引导器（唯一入口）
#
#  设计：真正的逻辑都在 script/ 目录的模块里（跟 NixOS 的 modules/ 一个思路）：
#    script/lib/*.sh        基础设施（env 配置 / util 输出菜单 / selection 模块选择）
#    script/commands/*.sh   命令（install / update / menu / rollback / dashboard）
#    script/main.sh         加载以上所有模块并路由
#
#  本文件只做三件事：
#    1. 找到模块在哪（脚本自身所在目录，或当前目录）
#    2. 找不到（比如 curl|bash 单文件管道）→ 从 GitHub 拉取最新代码到临时目录
#    3. 加载 script/main.sh 并传递参数
#
#  用法见 script/commands 和 README：
#    ut                    # 管理面板（等价于 sudo install.sh）
#    bash install.sh menu  # 更换模块
#    curl -L <url>/install.sh | sudo bash -s -- --rollback   # 保险回滚
# ============================================================================
set -euo pipefail

# ---- 语言选择（引导阶段最小实现；完整 i18n 由 script/lib/i18n.sh 提供）----
# 与 script/lib/i18n.sh 的 detect_lang 保持一致，_t 则在该模块加载后接管。
_boot_lang() {
  local forced="${UTNIXOS_PRO_LANG:-}"
  if [[ -n "$forced" ]]; then
    case "$forced" in
      zh|zh_*|cn|Chinese|chinese) echo zh ;;
      *) echo en ;;
    esac
    return
  fi
  # Linux 虚拟控制台（TERM=linux）字体不含中文字形（显示成方块）→ 英文
  [[ "${TERM:-}" == "linux" ]] && { echo en; return; }
  case "${LC_ALL:-${LANG:-}}" in
    zh*|zh_*) echo zh ;;
    *) echo en ;;
  esac
}
LANG_UI="$(_boot_lang)"
_tb() { # _tb <中文> <英文>
  if [[ "$LANG_UI" == "zh" ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# ---- 引导所需的最小配置（完整配置在 script/lib/env.sh）----
GIT_URL="${UTNIXOS_PRO_GIT_URL:-https://github.com/Reimilia617/UTNixOS_Pro.git}"
TARBALL_URL="${UTNIXOS_PRO_TARBALL_URL:-https://github.com/Reimilia617/UTNixOS_Pro/archive/refs/heads/main.tar.gz}"

SCRIPT_SRC=""

# 1) 直接执行（bash install.sh / sudo /etc/nixos/install.sh）：用脚本自己旁边的模块
if [[ "$0" == *"install.sh" && -f "$0" ]]; then
  d="$(cd "$(dirname "$0")" && pwd)"
  if [[ -f "$d/script/main.sh" ]]; then
    SCRIPT_SRC="$d"
  fi
fi

# 2) curl|bash（$0=bash 找不到自己）或路径奇怪：检查当前目录
if [[ -z "$SCRIPT_SRC" && -f "./script/main.sh" ]]; then
  SCRIPT_SRC="$(pwd)"
fi

# 3) 都没有 → 引导模式：从 GitHub 拉取最新代码
if [[ -z "$SCRIPT_SRC" ]]; then
  # 解析 --no-apple（不下载 badapple.mp4，加快拉取）
  no_apple=0
  for _a in "$@"; do
    [[ "$_a" == "--no-apple" ]] && no_apple=1
  done

  BOOT_TMP="$(mktemp -d)"
  trap 'rm -rf "$BOOT_TMP"' EXIT
  echo "[*] $(_tb "正在从 GitHub 获取 UTNixOS_Pro 脚本..." "Fetching UTNixOS_Pro scripts from GitHub...")"

  # 代理透传：这里不是函数，不能用 local。git/curl 都显式带上环境变量里的代理
  # （很多人只给外层 curl 加了 -x，内层 git clone/curl 不走代理 → 卡在 fetch）
  _proxy="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
  git_proxy=()
  curl_proxy=()
  if [[ -n "$_proxy" ]]; then
    git_proxy=(-c "http.proxy=$_proxy" -c "https.proxy=$_proxy")
    curl_proxy=(-x "$_proxy")
    echo "    $(_tb "使用代理：" "using proxy:") $_proxy"
  fi
  # 防挂起：git 低速 30 秒即中止（避免断网时无限卡在 fetch）；curl 给连接/总超时
  git_slow=(--config http.lowSpeedLimit=1000 --config http.lowSpeedTime=30)
  export GIT_TERMINAL_PROMPT=0   # 需要凭据时直接失败，而不是卡在交互提示

  if command -v git >/dev/null 2>&1; then
    # 注意：clone 失败不能触发 set -e 退出，必须留给下面的 curl|tar 回退分支。
    if [[ "$no_apple" == "1" ]]; then
      # 稀疏检出：跳过 media/（badapple.mp4），加快下载
      if ! { git clone "${git_proxy[@]}" --depth 1 --filter=blob:none --sparse "${git_slow[@]}" "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1 \
        && git -C "$BOOT_TMP" sparse-checkout set --no-cone '/*' '!/media/' >/dev/null 2>&1; }; then
        # 稀疏检出失败 → 回退普通克隆
        rm -rf "$BOOT_TMP"
        if ! git clone "${git_proxy[@]}" --depth 1 "${git_slow[@]}" "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1; then
          rm -rf "$BOOT_TMP"; mkdir -p "$BOOT_TMP"   # 仍失败 → 交给 tarball 回退
        fi
      fi
    else
      if ! git clone "${git_proxy[@]}" --depth 1 "${git_slow[@]}" "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1; then
        rm -rf "$BOOT_TMP"; mkdir -p "$BOOT_TMP"   # clone 失败 → 交给 tarball 回退
      fi
    fi
  fi
  if [[ ! -f "$BOOT_TMP/script/main.sh" ]] && command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL "${curl_proxy[@]}" --connect-timeout 15 --max-time 600 "$TARBALL_URL" | tar -xz -C "$BOOT_TMP" --strip-components=1; then
      echo "[✗] $(_tb "获取 UTNixOS_Pro 代码失败，请检查网络/代理" "Failed to fetch UTNixOS_Pro code, please check your network/proxy")" >&2
      echo "    $(_tb "提示：先 export https_proxy=http://代理地址:端口 再重试；也可加 --no-apple 跳过视频加快" "Hint: run 'export https_proxy=http://proxy:port' first and retry; add --no-apple to skip the video")" >&2
      exit 1
    fi
    [[ "$no_apple" == "1" ]] && rm -f "$BOOT_TMP/media/badapple.mp4"
  fi
  if [[ ! -f "$BOOT_TMP/script/main.sh" ]]; then
    echo "[✗] $(_tb "拉取到的代码不完整（缺少 script/main.sh）" "Fetched code is incomplete (missing script/main.sh)")" >&2
    exit 1
  fi
  SCRIPT_SRC="$BOOT_TMP"
fi

# 加载全部模块并进入主程序
# shellcheck source=script/main.sh
source "$SCRIPT_SRC/script/main.sh" "$@"
