{ config, lib, pkgs, ... }:

{
  # ut 命令：UTNixOS_Pro 管理总接口
  # 用法：ut          → 打开管理面板（重建/清理/选模块/更新/回滚/一键修复）
  #       ut update   → 更新配置
  #       ut menu     → 更换模块
  #       ut rollback → 系统回滚
  #       ut repair   → 一键修复（/etc/nixos 损坏时自动进入）
  # 实现上就是把参数透传给 /etc/nixos/install.sh。
  # 注意用「sudo bash」而不是直接执行：某些部署方式下 install.sh 的可执行位
  # 可能丢失，直接执行会报「command not found」，bash 显式调用则不受影响。
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "ut" ''
      exec sudo bash /etc/nixos/install.sh "$@"
    '')
  ];
}
