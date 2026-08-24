{ pkgs, ... }:

let
  # 壁纸随 flake 一起进入 Nix store，不再依赖 /etc/nixos 下的绝对路径
  # （否则配置放在其他目录时壁纸会静默失效）
  wallpaper = ../../themes/wallpapers/youmu.png;
in
{
  services.xserver.enable = true;

  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;

  # Default Wallpaper
  services.xserver.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.desktop.background]
    picture-uri='file://${wallpaper}'
    picture-uri-dark='file://${wallpaper}'
  '';
}