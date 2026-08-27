{ pkgs, ... }:

{
  programs.fish = {
    enable = true;

    # fish 的别名（注意：fish 的别名和 zsh/bash 的 shellAliases 是两套，
    # 所以这里单独定义，与 home/terminal.nix 保持一致）
    shellAliases = {
      # 用 sudo bash 显式执行：install.sh 的可执行位可能丢失（某些部署方式），
      # 直接执行会报 command not found；别名会覆盖系统的 ut 二进制，必须保持一致
      ut = "sudo bash /etc/nixos/install.sh";
      sys-update = "sudo nixos-rebuild switch --flake /etc/nixos#reimilia";
      clean = "sudo nix-collect-garbage -d";
      ff = "hyfetch";
      ll = "ls -al";
      la = "ls -la";
    };
  };
}
