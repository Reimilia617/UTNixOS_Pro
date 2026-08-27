{ config, pkgs, ... }:

{
  # GRUB (BIOS/传统 MBR 启动)
  # 目标磁盘（如 /dev/sda）不写死在这里：由安装脚本/Web 面板在
  # 选择「GRUB(BIOS)」时写入机器本地文件 host/grub-device.nix。
  boot.loader.grub = {
    enable = true;
    useOSProber = true;     #自动检测其他系统
    # configurationLimit 在 modules/system/clean.nix 中统一设置（仅在 GRUB 启用时生效）
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
}
