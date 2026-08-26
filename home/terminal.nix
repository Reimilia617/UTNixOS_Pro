{ pkgs, ... }:

{
  # 环境变量
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
    PAGER = "less";
    BROWSER = "firefox";
  };

  # 别名
  home.shellAliases = {
    # ut：UTNixOS_Pro 管理总接口（打开管理面板：重建/清理/选模块/更新/回滚）
    ut = "sudo /etc/nixos/install.sh";
    # 使用绝对路径，避免依赖当前工作目录（与 system.autoUpgrade 的 flake 路径保持一致）
    sys-update = "sudo nixos-rebuild switch --flake /etc/nixos#reimilia";
    clean = "sudo nix-collect-garbage -d";
    ff = "hyfetch";
    ll = "ls -al";
    la = "ls -la";
  };
}