#!/usr/bin/env bash
# ============================================================================
#  UTNixOS - 管理脚本引导器（唯一入口）
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

# ---- 引导所需的最小配置（完整配置在 script/lib/env.sh）----
GIT_URL="${UTNIXOS_GIT_URL:-https://github.com/Reimilia617/UTNixOS.git}"
TARBALL_URL="${UTNIXOS_TARBALL_URL:-https://github.com/Reimilia617/UTNixOS/archive/refs/heads/main.tar.gz}"

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
  echo "[*] 正在从 GitHub 获取 UTNixOS 脚本..."
  if command -v git >/dev/null 2>&1; then
    # 注意：clone 失败不能触发 set -e 退出，必须留给下面的 curl|tar 回退分支。
    if [[ "$no_apple" == "1" ]]; then
      # 稀疏检出：跳过 media/（badapple.mp4），加快下载
      if ! { git clone --depth 1 --filter=blob:none --sparse "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1 \
        && git -C "$BOOT_TMP" sparse-checkout set --no-cone '/*' '!/media/' >/dev/null 2>&1; }; then
        # 稀疏检出失败 → 回退普通克隆
        rm -rf "$BOOT_TMP"
        if ! git clone --depth 1 "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1; then
          rm -rf "$BOOT_TMP"; mkdir -p "$BOOT_TMP"   # 仍失败 → 交给 tarball 回退
        fi
      fi
    else
      if ! git clone --depth 1 "$GIT_URL" "$BOOT_TMP" >/dev/null 2>&1; then
        rm -rf "$BOOT_TMP"; mkdir -p "$BOOT_TMP"   # clone 失败 → 交给 tarball 回退
      fi
    fi
  fi
  if [[ ! -f "$BOOT_TMP/script/main.sh" ]] && command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$BOOT_TMP" --strip-components=1 \
      || { echo "[✗] 获取 UTNixOS 代码失败，请检查网络" >&2; exit 1; }
    [[ "$no_apple" == "1" ]] && rm -f "$BOOT_TMP/media/badapple.mp4"
  fi
  if [[ ! -f "$BOOT_TMP/script/main.sh" ]]; then
    echo "[✗] 拉取到的代码不完整（缺少 script/main.sh）" >&2
    exit 1
  fi
  SCRIPT_SRC="$BOOT_TMP"
fi

# 加载全部模块并进入主程序
# shellcheck source=script/main.sh
source "$SCRIPT_SRC/script/main.sh" "$@"
