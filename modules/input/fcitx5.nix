{ pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5.addons = with pkgs; [
      fcitx5-rime
      #fcitx5-chinese-addons     # 中文支持
      #fcitx5-gtk     # GTK插件
      #fcitx5-qt     #QT插件
    ];
  };
}