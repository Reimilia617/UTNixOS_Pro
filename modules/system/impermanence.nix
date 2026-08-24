# impermanence 根文件系统不持久化模板（默认关闭）
#
# 作用：根分区每次重启还原到初始状态（类似"无状态系统"），
#       只有 /persist 里的内容会保留。适合对系统洁癖、或想防止配置漂移的人。
#
# 警告：启用前请仔细阅读 https://github.com/nix-community/impermanence
#       并做好数据迁移，否则重启后非持久化数据会丢失！
#
# 注意：impermanence 模块已在 flake.nix 中导入，这里只负责具体配置。
{ config, lib, pkgs, ... }:

{
  # environment.persistence."/persist" = {
  #   hideMounts = true;
  #   directories = [
  #     "/var/log"
  #     "/var/lib/bluetooth"
  #     "/var/lib/NetworkManager"
  #     "/var/lib/systemd/coredump"
  #   ];
  #   files = [ "/etc/machine-id" ];
  #   users.reimilia = {
  #     directories = [
  #       "Downloads"
  #       "Documents"
  #       "Pictures"
  #       ".config"
  #       ".local/share"
  #       ".ssh"
  #     ];
  #   };
  # };
}
