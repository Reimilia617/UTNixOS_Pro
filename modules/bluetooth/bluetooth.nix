{ config, pkgs, ...}:

{
  # Hardware Supported Bluetooth
  hardware.bluetooth.enable = true;

  # Blueman Tools
  services.blueman.enable = true;

  # If you need CLI Tools
  #environment.systemPackages = with pkgs; [
  #  bluez
  #  bluez-tools
  #];
}