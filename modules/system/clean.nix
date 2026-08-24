{ config, lib, pkgs, ... }: {
    nix.gc = {
      automatic = true;
      dates = "03:15";
      options = "--delete-older-than 7d";
      persistent = true;
    };

  # Clean Bootloader
  # 仅在启用 GRUB 时生效（切换 systemd-boot 后自动失效），
  # 数值与 modules/boot/grub.nix 保持一致（grub.nix 中已不重复设置）
  boot.loader.grub.configurationLimit = lib.mkIf config.boot.loader.grub.enable 10;
}

