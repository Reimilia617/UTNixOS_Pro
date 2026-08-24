# ⚠️⚠️⚠️ 警告：这是一个【示例】文件！请勿直接部署到真实机器！⚠️⚠️⚠️
#
# 它的作用只是让仓库在没有真实机器的情况下也能通过评测/CI（nix flake check 等）。
# 本示例面向 QEMU/KVM 虚拟机（virtio 磁盘），根分区指向 /dev/vda1，
# 真实机器（NVMe/SATA、NVIDIA 显卡、双系统等）直接使用会无法启动！
#
# 在你的真实机器上，请生成属于你自己的硬件配置：
#   安装时：  nixos-generate-config --root /mnt
#   已装系统：sudo nixos-generate-config --dir /etc/nixos
# 然后用生成的文件替换本文件（README 安装流程第 3/4 步）。
#
# 注意：NixOS 系统会把 /etc/nixos/hardware-configuration.nix 保留为机器专属，
# 升级配置时不要用仓库里的这份示例覆盖它。
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "ata_piix" "virtio_blk" "virtio_pci" "virtio_net" "uhci_hcd" "ehci_pci" ];
  boot.kernelModules = [ ];

  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
