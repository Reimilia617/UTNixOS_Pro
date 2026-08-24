{ pkgs, ... }:

{
  # Fish Shell（作为系统默认 Shell 时启用本模块）
  # 注意：与 modules/shell/{zsh,bash}.nix 二选一，别同时开
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;
}
