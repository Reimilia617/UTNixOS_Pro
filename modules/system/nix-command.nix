{ config, pkgs, ... }: {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;  # 自动硬链接去重，节省空间
}