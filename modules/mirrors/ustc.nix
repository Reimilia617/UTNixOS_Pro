{ config, pkgs, ... }:

{
  # 中科大镜像源
  nix.settings = {
    # 优先使用中科大镜像
    substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"    # 备用官方源
    ];

    #信任的镜像源
    trusted-substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];
  };
}