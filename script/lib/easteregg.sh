# UTNixOS_Pro 彩蛋模块（script/lib/easteregg.sh）
# 在模块选择界面输入 "touhou"（大小写不限）回车，播放 Bad Apple!! 影绘.mp4
#
# 文件位置：media/badapple.mp4（随仓库一起部署）
#   - live 安装/脚本运行期间：$(SCRIPT_SRC)/media/badapple.mp4
#   - 已安装系统：/etc/nixos/media/badapple.mp4
# 用 --no-apple 安装的系统没有该文件，彩蛋会提示而不是报错。

# 查找 badapple.mp4（返回第一个找到的路径）
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

# 播放 Bad Apple!!
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

# 判断输入是否是彩蛋口令（大小写不限，允许带标点/空格）
is_touhou() {
  local input
  input="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:] ')"
  [[ "$input" == "touhou" ]]
}
