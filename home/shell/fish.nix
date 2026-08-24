{ pkgs, ... }:

{
  programs.fish = {
    enable = true;

    # fish 的别名（注意：fish 的别名和 zsh/bash 的 shellAliases 是两套，
    # 所以这里单独定义，与 home/terminal.nix 保持一致）
    shellAliases = {
      ut = "sudo /etc/nixos/install.sh";
      sys-update = "sudo nixos-rebuild switch --flake /etc/nixos#reimilia";
      clean = "sudo nix-collect-garbage -d";
      ff = "hyfetch";
      ll = "ls -al";
      la = "ls -la";
    };
  };
}
