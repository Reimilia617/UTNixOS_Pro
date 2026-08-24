# disko 声明式分区示例（默认不使用，仅作模板）
#
# 作用：用配置文件描述磁盘分区，替代 cfdisk 手动分区。
# 用法（全新安装时）：
#   1. 按需修改下面的磁盘/分区/挂载点
#   2. 执行：sudo nix run github:nix-community/disko -- --mode disko ./disko-config.nix
#      （这会格式化整个磁盘！请确认磁盘设备号无误）
#   3. 然后照常：nixos-generate-config --root /mnt && 运行安装脚本
#
# 本示例：UEFI + GPT，ESP 挂 /boot，根分区 ext4 挂 /
{ disks ? [ "/dev/nvme0n1" ], ... }:
{
  disk.main = {
    type = "disk";
    device = builtins.elemAt disks 0;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
