{
  # X11
  services.xserver.enable = true;

  # Enable XFCE
  services.xserver.desktopManager.xfce.enable = true;

  # Enable SDDM
  services.displayManager.sddm.enable = true;
}