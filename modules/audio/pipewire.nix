{ config, pkgs, ...}:

{
  # Pipewire
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you need the jack support,please delete "#" under the this
    #jack.enable = true;
  };

  # Allow Users use Audio
  security.rtkit.enable = true;
}