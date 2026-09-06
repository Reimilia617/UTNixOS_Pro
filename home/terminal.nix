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
    # ut 已是系统内置二进制（modules/system/ut.nix）：快捷启动 Web 管理面板，
    # 因此这里不定义别名覆盖它（历史上别名 sudo bash install.sh 曾遮蔽/冲突系统 ut）。
    # 使用绝对路径，避免依赖当前工作目录（与 system.autoUpgrade 的 flake 路径保持一致）
    sys-update = "sudo nixos-rebuild switch --flake /etc/nixos#reimilia";
    clean = "sudo nix-collect-garbage -d";
    ff = "hyfetch";
    ll = "ls -al";
    la = "ls -la";
  };
}