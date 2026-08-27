# UTNixOS_Pro 脚本通用工具（script/lib/util.sh）
# 输出 / 菜单 / sed 工具 / ASCII 画。不依赖其他模块（除 env.sh 的颜色变量）。

# ---------- 输出（优先写 /dev/tty，兼容 curl | bash；无 tty 时回退 stdout）----------
# 所有输出函数都经过 _t 翻译：第一个参数为 i18n 键（见 script/lib/i18n.sh），
# 其余为格式串 %s 的参数；传入非键的普通字符串时原样输出。
_tty_out() {
  # 尝试写 /dev/tty（交互终端）；失败（无tty/管道环境）则回退 stdout
  if { printf '%b' "$*" > /dev/tty; } 2>/dev/null; then :; else printf '%b' "$*"; fi
}
say()  { _tty_out "$(_t "$@")\n"; }
info() { _tty_out "${C_CYAN}[*]${C_RESET} $(_t "$@")\n"; }
ok()   { _tty_out "${C_GREEN}[✓]${C_RESET} $(_t "$@")\n"; }
warn() { _tty_out "${C_YELLOW}[!]${C_RESET} $(_t "$@")\n"; }
die()  { _tty_out "${C_RED}[✗]${C_RESET} $(_t "$@")\n"; exit 1; }
prompt() { _tty_out "$(_t "$@")"; }

# ---------- ASCII 字符画 ----------
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

# ---------- 菜单：单选 ----------
PICKED=""

# 选项显示名：优先 opt_<name> 的翻译（i18n），找不到就显示原始模块名。
# 例：auto-update → 「自动更新(auto-update)」；en_US 等无翻译的保持原名。
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

# 空格分隔的值列表 → 逐个转显示名（如 "auto-update clean" → "自动更新(auto-update) 自动清理垃圾(clean)"）
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
      printf '  %2d) %s\n' $((i+1)) "$(opt_label "${names[$i]}")" > /dev/tty
    done
    prompt menu_choose "$n"
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
      printf '  %2d) %s %s\n' $((i+1)) "$mark" "$(opt_label "${names[$i]}")" > /dev/tty
    done
    prompt multi_prompt
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
# 防挂起：git 低速 30 秒即中止（断网时不会无限卡住）；git 本身会读 http_proxy/https_proxy 环境变量
clone_config() {
  local dest="$1"
  export GIT_TERMINAL_PROMPT=0
  local slow=(--config http.lowSpeedLimit=1000 --config http.lowSpeedTime=30)
  if [[ "${NO_APPLE:-0}" == "1" ]] && git --version >/dev/null 2>&1; then
    if git clone --depth 1 --filter=blob:none --sparse "${slow[@]}" "$GIT_URL" "$dest" >/dev/null 2>&1 \
      && git -C "$dest" sparse-checkout set --no-cone '/*' '!/media/' >/dev/null 2>&1; then
      return 0
    fi
    rm -rf "$dest"    # 稀疏检出失败 → 回退普通克隆（部署时再排除 mp4）
  fi
  git clone --depth 1 "${slow[@]}" "$GIT_URL" "$dest" >/dev/null 2>&1
}
