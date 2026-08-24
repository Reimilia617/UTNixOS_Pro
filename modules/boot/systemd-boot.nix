{ config, pkgs, ... }:

{
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;

# Open systemd-boot Auto Menu
boot.loader.systemd-boot.memtest86.enable = true;

# Used Latest Linux Kernel
boot.kernelPackages = pkgs.linuxPackages_latest;
}