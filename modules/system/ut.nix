{ config, lib, pkgs, ... }:

# ut 命令：快捷启动 Web 管理面板（UTNixOS_Pro 的唯一管理入口）
#
# 日常管理已经全部交给 Web 面板（Go 后端 + systemd 守护进程常驻）：
#   ut            # 打开 http://127.0.0.1:8090
#
# 行为：
#   1. 检查 systemd 服务 utnixos-pro-webui 是否运行；
#      未运行则自动尝试拉起：
#        - 已是 root        → systemctl start
#        - 图形会话 + polkit → pkexec systemctl start（弹出授权框）
#        - 否则（SSH/无头） → 打印提示，让用户 sudo systemctl start
#   2. 有桌面会话时用 xdg-open（或 $BROWSER）打开面板，无图形则打印地址。
#   3. 提示用系统用户名/密码（wheel 组）登录。
#
# 说明：ut 现在是系统内置二进制（不再透传给 install.sh，也不被 shell 别名覆盖；
#   install.sh 只保留 安装/修复配置/UT紧急回滚 三类用途）。

let
  webui = config.services."utnixos-pro-webui";
  addr  = webui.address or "127.0.0.1";
  port  = toString (webui.port or 8090);
  url   = "http://${addr}:${port}";
in
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "ut" ''
      # ut: quick-launch the Web management panel (ensure systemd service + open browser)
      set -u

      URL="http://${addr}:${port}"
      UNIT="utnixos-pro-webui"

      # minimal bilingual (same rule as install.sh): TERM=linux console has no CJK glyphs
      LANG_UI=en
      if [[ -n "''${UTNIXOS_PRO_LANG:-}" ]]; then
        case "$UTNIXOS_PRO_LANG" in
          zh|zh_*|cn|Chinese|chinese) LANG_UI=zh ;;
          *) LANG_UI=en ;;
        esac
      elif [[ "''${TERM:-}" != linux ]]; then
        case "''${LC_ALL:-''${LANG:-}}" in
          zh*|zh_*) LANG_UI=zh ;;
        esac
      fi
      msg() { # msg <zh> <en>
        if [[ "$LANG_UI" == zh ]]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
      }

      # ---------- 1) 确保服务在跑 ----------
      up=0
      if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
        up=1
      elif [[ "$(id -u)" == "0" ]]; then
        systemctl start "$UNIT" 2>/dev/null && up=1
      elif command -v pkexec >/dev/null 2>&1 && [[ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]]; then
        if pkexec systemctl start "$UNIT"; then up=1; else
          msg "未能启动面板服务（授权被取消或失败）。请手动执行：sudo systemctl start $UNIT" \
              "Could not start the panel service. Please run: sudo systemctl start $UNIT"
        fi
      fi

      if [[ "$up" != "1" ]]; then
        if systemctl is-active --quiet "$UNIT" 2>/dev/null; then up=1; fi
      fi

      if [[ "$up" != "1" ]]; then
        msg "" "The Web panel service ($UNIT) is not running."
        msg "请先启动服务（需要 root）：sudo systemctl start $UNIT" \
            "Start it first (root required):  sudo systemctl start $UNIT"
        msg "然后再次运行 ut（或在浏览器打开 $URL）。" \
            "Then run ut again (or open $URL in your browser)."
        msg "登录：系统用户名/密码（wheel 组）。" "Login: system username/password (wheel group)."
        exit 1
      fi

      # 等 HTTP 就绪（curl 存在时最多等 10 秒，避免开了浏览器页面还没起来）
      if command -v curl >/dev/null 2>&1; then
        i=0
        while [[ $i -lt 20 ]]; do
          curl -fs -m 1 "$URL/api/health" >/dev/null 2>&1 && break
          sleep 0.5
          i=$((i+1))
        done
      fi

      # ---------- 2) 打开 / 打印面板地址 ----------
      if [[ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]]; then
        if command -v xdg-open >/dev/null 2>&1; then
          (xdg-open "$URL" >/dev/null 2>&1 &) || true
          msg "正在打开 Web 管理面板：$URL" "Opening the Web management panel: $URL"
        elif [[ -n "''${BROWSER:-}" ]]; then
          ("$BROWSER" "$URL" >/dev/null 2>&1 &) || true
          msg "正在打开 Web 管理面板：$URL" "Opening the Web management panel: $URL"
        else
          msg "请在浏览器打开：$URL" "Open this URL in your browser: $URL"
        fi
      else
        msg "Web 管理面板：$URL" "Web management panel: $URL"
        msg "（无图形会话，未自动打开浏览器；可用 SSH 隧道：ssh -L 8090:127.0.0.1:8090 主机名）" \
            "(no graphical session, browser not auto-opened; SSH tunnel: ssh -L 8090:127.0.0.1:8090 host)"
      fi
      msg "登录：系统用户名/密码（wheel 组）。管理操作会实时记录到审计日志。" \
          "Login: system username/password (wheel group). All actions are audited."
      exit 0
    '')
  ];
}
