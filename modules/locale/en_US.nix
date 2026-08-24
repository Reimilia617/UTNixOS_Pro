{ config, pkgs, ... }:

{
  # System Language
  i18n.defaultLocale = "en_US.UTF-8";

  # Console KeyMap
  console.keyMap = "us";

  # X11 KeyMap
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}