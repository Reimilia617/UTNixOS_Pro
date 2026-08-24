{ config, lib, pkgs, ... }:

{
  # 字体（默认启用，中英文环境都适用）
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    (nerd-fonts.jetbrains-mono)     # Nerd Font，终端图标/状态栏必备
  ];

  # 系统默认字体
  fonts.fontconfig.defaultFonts = {
    serif = [ "Noto Serif CJK SC" "DejaVu Serif" ];
    sansSerif = [ "Noto Sans CJK SC" "DejaVu Sans" ];
    monospace = [ "JetBrainsMono Nerd Font" "DejaVu Sans Mono" ];
  };
}
