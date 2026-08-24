{ config, pkgs, ... }:

{
  # Network
  networking.networkmanager.enable = true;

  # 防火墙（默认开启；需要对外提供端口服务时在这里显式声明）
  networking.firewall = {
    enable = true;
    # allowedTCPPorts = [ 22 8080 ];     # SSH / Web
    # allowedUDPPorts = [ 5353 ];        # mDNS
  };

  # Hostname
  networking.hostName = "reimilia";

  # TimeZone
  time.timeZone = "Asia/Shanghai";

  # Optional:Network Tools
  #environment.systemPackages = with pkgs; [
  #  networkmanagerapplet     # NetworkManager GUI
  #  nmap     # Network Scan Tools
  #];
}