{ pkgs, ... }:

{
  imports = [
    ./packages.nix
    ./programs.nix     # 常用程序的声明式配置(git/ssh/fzf等)
    ./shell/zsh.nix     #默认使用ZSH
    #./shell/bash.nix     #可选Bash
    #./shell/fish.nix     #可选Fish
    ./terminal.nix
  ];

  home.stateVersion = "26.05";
  home.username = "reimilia";
  home.homeDirectory = "/home/reimilia";

  # XDG 目录规范：~/.config ~/.local 等统一管理，目录更干净
  xdg.enable = true;
}