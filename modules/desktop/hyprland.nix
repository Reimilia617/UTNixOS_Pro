{ config, pkgs, ... }:

  {
    programs.hyprland.enable = true;

    # Hyprland 本身不附带登录管理器，这里补上 SDDM 才能正常登录进桌面
    # （Hyprland 会出现在 SDDM 的 Wayland 会话列表中）
    # 注意：Hyprland 是纯 Wayland 环境，不启用 X11，
    # 所以必须开启 SDDM 的 Wayland greeter，否则会触发断言：
    #   "SDDM requires either services.xserver.enable or services.displayManager.sddm.wayland.enable to be true"
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    xdg.portal.enable = true;
    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
    ];
  }