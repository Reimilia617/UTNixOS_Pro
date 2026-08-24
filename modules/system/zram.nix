{ config, pkgs, ... }: {
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;     # Use 50% to ZRAM
}