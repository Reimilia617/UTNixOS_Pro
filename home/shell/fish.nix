{ pkgs, ... }:

{
  programs.fish = {
    enable = true;

    # fish 的别名（注意：fish 的别名和 zsh/bash 的 shellAliases 是两套，
    # 所以这里单独定义，与 home/terminal.nix 保持一致）
    shellAliases = {
      # ut 已是系统内置二进制（modules/system/ut.nix）：快捷启动 Web 管理面板，
      # 不在此定义别名（fish 别名会覆盖系统命令，历史上曾遮蔽系统 ut）。
      sys-update = "sudo nixos-rebuild switch --flake /etc/nixos#reimilia";
      clean = "sudo nix-collect-garbage -d";
      ff = "hyfetch";
      ll = "ls -al";
      la = "ls -la";
    };
  };
}
