{ config, pkgs, ... }:

{
  # 中文语言环境
  i18n.defaultLocale = "zh_CN.UTF-8";

  # 额外语言支持
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "zh_CN.UTF-8/UTF-8"
  ];

  # 键盘布局
  console.keyMap = "us";

  # X11中文键盘
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # 字体已统一在 modules/system/fonts.nix 中配置（中英文环境通用）
}