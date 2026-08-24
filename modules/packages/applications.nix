{ config, pkgs, ... }:

{
  # allow non-free packages
  nixpkgs.config.allowUnfree = true;

  # System Packages
  environment.systemPackages = with pkgs; [
    # Edit
    nano
    vim

    # Network Tools
    networkmanager
    curl
    wget
    git

    # SystemTools
    hyfetch     # 系统信息展示(neofetch系,支持自定义配色彩虹旗)
    unzip
    openssh

    # 注意：os-prober 在 boot.loader.grub.useOSProber=true 时由 NixOS 自动添加；
    # networkmanager 包由 services.networking.networkmanager 自动添加，均无需重复安装

    # 忘记加浏览器了qaq
    firefox
  ];
}