{ config, lib, pkgs, ... }:

# UTNixOS_Pro Web 管理面板（默认关闭，用 `ut menu` 或 Web 面板自身开启）
#
# 功能：系统用户名/密码（PAM）登录，浏览器访问
#   http://127.0.0.1:8090   （默认仅本机，不会暴露到公网）
# 提供：重建系统 / 更新系统 / 模块启停（读写 configuration.nix）/
#       时间点回滚（generations）/ 实时日志 / 清理构建垃圾 / 审计。
#
# 安全提醒：
#   - 默认只监听 127.0.0.1。想在内网其他设备访问时：
#     方案A（推荐）：保持 127.0.0.1，用 SSH 隧道 ssh -L 8090:127.0.0.1:8090 user@主机
#     方案B：设置 address = "0.0.0.0"（或内网 IP）并 allowLan = true 开放防火墙端口，
#            此时登录密码会以明文走网络，务必自备 HTTPS 反代或仅在可信内网使用。
#   - 面板以 root 运行（需要执行 nixos-rebuild），只允许 wheel 组用户登录（可改 allowedGroup）。

let
  cfg = config.services."utnixos-pro-webui";
in
{
  options.services."utnixos-pro-webui" = {
    enable = lib.mkEnableOption "UTNixOS_Pro Web 管理面板";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Web 管理端口。";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        监听地址。默认仅本机可访问（最安全，不暴露任何端口）。
        如需内网访问请改成内网 IP 或 "0.0.0.0"，并配合 allowLan 开防火墙；
        切勿直接暴露到公网。
      '';
    };

    allowLan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "允许内网访问（在防火墙上开放 port）。默认 false：仅本机可访问。";
    };

    allowedGroup = lib.mkOption {
      type = lib.types.str;
      default = "wheel";
      description = "允许登录管理面板的系统用户组（PAM 认证通过后还会校验该组）。留空=任意系统用户。";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs."utnixos-pro-webui";
      description = "Web 管理面板程序包（来自 overlays/default.nix 的自建包）。";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services."utnixos-pro-webui" = {
      description = "UTNixOS_Pro Web 管理面板";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # 服务 PATH 里带上面板依赖的命令（nix/nixos-rebuild/git/pamtester/journalctl）
      path = [
        pkgs."utnixos-pro-webui"
        pkgs.nix
        pkgs.git
        pkgs.pamtester
        pkgs.nixos-rebuild
        pkgs.coreutils
        pkgs.gnused
        pkgs.gawk
        pkgs.systemd
      ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/webui --addr ${cfg.address}:${toString cfg.port} --config-dir /etc/nixos --state-dir /var/lib/utnixos-pro-webui --pam-service utnixos-pro-webui --allowed-group ${cfg.allowedGroup}";
        Restart = "on-failure";
        RestartSec = "3";
        # 审计日志目录（/var/lib/utnixos-pro-webui）
        StateDirectory = "utnixos-pro-webui";
      };
    };

    # PAM 认证服务：pamtester 用它验证系统用户密码
    security.pam.services."utnixos-pro-webui" = { };

    # 默认不开防火墙端口（仅本机）；允许内网访问时才开放
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.allowLan [ cfg.port ];

    environment.systemPackages = [ cfg.package ];
  };
}
