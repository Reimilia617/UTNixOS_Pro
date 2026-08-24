{ config, pkgs, ... }:

{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    devices = [ "nodev" ];
    useOSProber = true;     #自动检测其他大鸡巴系统
    # configurationLimit 在 modules/system/clean.nix 中统一设置（仅在 GRUB 启用时生效）
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
}