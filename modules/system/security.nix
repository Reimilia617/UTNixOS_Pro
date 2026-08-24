# 安全模板（默认关闭）
#
# fail2ban：自动封禁暴力破解 SSH 等服务的 IP。
# 对常开 SSH 的机器强烈建议开启；纯家用桌面可不开。
{ config, lib, pkgs, ... }:

{
  # services.fail2ban.enable = true;
  # services.fail2ban.maxretry = 5;
  # services.fail2ban.bantime = "1h";
  # services.fail2ban.ignoreIP = [ "127.0.0.1/8" "192.168.0.0/16" ];
}
