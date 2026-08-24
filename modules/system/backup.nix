# restic 定时备份模板（默认关闭）
#
# 作用：每天自动把指定目录备份到远程/本地 restic 仓库。
#
# 启用步骤：
#   1. 先手动初始化仓库：restic init --repo <repository>（或在配置里开 initialize）
#   2. 准备好密码文件（可以用 sops 或 chmod 600 的普通文件）
#   3. 取消下面注释，按需修改
{ config, lib, pkgs, ... }:

{
  # services.restic.backups.home = {
  #   repository = "sftp:user@nas:/backup/utnixos";
  #   passwordFile = "/etc/nixos/restic-password";
  #   paths = [
  #     "/home/reimilia/Documents"
  #     "/home/reimilia/Pictures"
  #   ];
  #   timerConfig = {
  #     OnCalendar = "daily";
  #     Persistent = true;
  #   };
  #   initialize = true;                        # 仓库不存在时自动创建
  #   pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
  #   # 备份前自动拍 LVM/btrfs 快照可选：extraBackupArgs
  # };
}
