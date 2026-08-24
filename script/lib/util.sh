# UTNixOS 脚本通用工具（script/lib/util.sh）
# 输出 / 菜单 / sed 工具 / ASCII 画。不依赖其他模块（除 env.sh 的颜色变量）。

# ---------- 输出（优先写 /dev/tty，兼容 curl | bash；无 tty 时回退 stdout）----------
_tty_out() {
  # 尝试写 /dev/tty（交互终端）；失败（无tty/管道环境）则回退 stdout
  if { printf '%b' "$*" > /dev/tty; } 2>/dev/null; then :; else printf '%b' "$*"; fi
}
say()  { _tty_out "$*\n"; }
info() { _tty_out "${C_CYAN}[*]${C_RESET} $*\n"; }
ok()   { _tty_out "${C_GREEN}[✓]${C_RESET} $*\n"; }
warn() { _tty_out "${C_YELLOW}[!]${C_RESET} $*\n"; }
die()  { _tty_out "${C_RED}[✗]${C_RESET} $*\n"; exit 1; }
prompt() { _tty_out "$*"; }

# ---------- ASCII 字符画 ----------
banner() {
  say "${C_CYAN}"
  say '##     ## ######## ##    ## #### ##     ##  #######   ######  '
  say '##     ##    ##    ###   ##  ##   ##   ##  ##     ## ##    ## '
  say '##     ##    ##    ####  ##  ##    ## ##   ##     ## ##       '
  say '##     ##    ##    ## ## ##  ##     ###    ##     ##  ######  '
  say '##     ##    ##    ##  ####  ##    ## ##   ##     ##       ## '
  say '##     ##    ##    ##   ###  ##   ##   ##  ##     ## ##    ## '
  say ' #######     ##    ##    ## #### ##     ##  #######   ######  '
  say "${C_RESET}"
}

# ---------- 菜单：单选 ----------
PICKED=""
pick_one() {
  local title="$1"; shift
  local -a names=("$@")
  local n=${#names[@]}
  PICKED=""
  while :; do
    say ""
    say "${C_BOLD}== $title ==${C_RESET}"
    local i
    for ((i=0;i<n;i++)); do
      printf '  %2d) %s\n' $((i+1)) "${names[$i]}" > /dev/tty
    done
    prompt "请选择 [1-$n]（回车=默认第1项）: "
    local choice=""
    read -r choice < /dev/tty || choice="1"
    # 彩蛋：输入 touhou 播放 Bad Apple!!
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    if [[ -z "$choice" ]]; then choice="1"; fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      PICKED="${names[$((choice-1))]}"
      return 0
    fi
  done
}

# ---------- 菜单：多选开关 ----------
PICKED_MULTI=""
pick_multi() {
  local title="$1"
  local default_on="$2"; shift 2
  local -a names=("$@")
  local -A on=()
  local d
  for d in $default_on; do on[$d]=1; done
  local n=${#names[@]}
  say ""
  say "${C_BOLD}== $title （输入序号切换 [x]/[ ]，回车确认） ==${C_RESET}"
  while :; do
    local i
    for ((i=0;i<n;i++)); do
      local mark="[ ]"
      [[ ${on[${names[$i]}]:-0} -eq 1 ]] && mark="[x]"
      printf '  %2d) %s %s\n' $((i+1)) "$mark" "${names[$i]}" > /dev/tty
    done
    prompt "> "
    local choice=""
    read -r choice < /dev/tty || choice=""
    # 彩蛋：输入 touhou 播放 Bad Apple!!
    if is_touhou "$choice"; then
      play_badapple
      continue
    fi
    if [[ -z "$choice" ]]; then break; fi
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

# ---------- sed 辅助：注释/取消注释 imports ----------
# 注意：不能带行尾锚点 $，因为 import 行后面往往跟着 #注释（如 " #XFCE"）
# 用法：comment_import <配置文件> <路径正则，如 system/auto-update.nix>
comment_import() {
  local cfg="$1" pat="$2"
  sed -i -E "s|^([[:space:]]*)#?(\./modules/${pat}[^#]*)|\1#\2|" "$cfg"
}
uncomment_import() {
  local cfg="$1" pat="$2"
  sed -i -E "s|^([[:space:]]*)#(\./modules/${pat}[^#]*)|\1\2|" "$cfg"
}

# ---------- 配置源码获取（--no-apple 时跳过 badapple.mp4，加快下载）----------
# clone_config <目标目录>：优先 git clone；NO_APPLE=1 时用稀疏检出跳过 media/
# （--filter=blob:none --sparse 只在需要时下载大文件 blob，media 里的 mp4 不会下载）
clone_config() {
  local dest="$1"
  if [[ "${NO_APPLE:-0}" == "1" ]] && git --version >/dev/null 2>&1; then
    if git clone --depth 1 --filter=blob:none --sparse "$GIT_URL" "$dest" >/dev/null 2>&1 \
      && git -C "$dest" sparse-checkout set --no-cone '/*' '!/media/' >/dev/null 2>&1; then
      return 0
    fi
    rm -rf "$dest"    # 稀疏检出失败 → 回退普通克隆（部署时再排除 mp4）
  fi
  git clone --depth 1 "$GIT_URL" "$dest" >/dev/null 2>&1
}
