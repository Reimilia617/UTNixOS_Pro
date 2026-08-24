{ config, lib, pkgs, ... }:

{
  # ut 命令：UTNixOS 管理总接口
  # 用法：ut          → 打开管理面板（重建/清理/选模块/更新/回滚）
  #       ut update   → 更新配置
  #       ut menu     → 更换模块
  #       ut rollback → 系统回滚
  # 实现上就是把参数透传给 /etc/nixos/install.sh
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "ut" ''
      exec sudo /etc/nixos/install.sh "$@"
    '')
  ];
}
