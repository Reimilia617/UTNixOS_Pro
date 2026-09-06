{ config, lib, pkgs, ... }:

# UTNixOS_Pro Web 管理面板（内置常驻组件：模块随 configuration.nix 无条件导入）
#
# 角色：本系统唯一的「配置与管理」入口（去 Bash 脚本化之后）：
#   - Go 后端以 systemd 守护进程方式常驻（本文件定义 unit utnixos-pro-webui），
#     直接读写 /etc/nixos 下的配置文件（configuration.nix / home-manager.nix /
#     host/packages.nix / host/grub-device.nix / .utnixos-pro-selection），
#     并以参数数组方式执行 nixos-rebuild / nix / git / journalctl 等命令。
#   - 浏览器访问 http://127.0.0.1:8090（默认仅本机，不会暴露到公网）。
#   - 安装后请用 `ut` 命令快捷打开面板（见 modules/system/ut.nix）。
#
# 功能：重建系统 / 更新配置(同步 GitHub+重建) / 更新 Flake / 模块启停 /
#       软件包(声明式+临时) / 时间点回滚(generations) / 实时日志 / 清理垃圾 / 审计。
#
# 不再可选项：面板是系统内置，WebUI 模块页不再提供「启用/关闭」开关；
#   install.sh 的模块选择也不再包含 webui。想极端关闭只能手动在
#   configuration.nix 删除本模块导入（会导致 ut 失去管理入口，不推荐）。
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
    # 注意：默认 true（导入即启用）。面板是内置管理入口，请保持默认。
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "是否启用 UTNixOS_Pro Web 管理面板（内置组件，默认 true；请勿关闭）。";
    };

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
      description = "UTNixOS_Pro Web 管理面板（系统唯一管理入口）";
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
        # 守护进程：崩溃自动拉起；健康退出（如 systemctl stop）则保持停止
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
