{ config, pkgs, ... }:

{
  # 南京大学镜像源
  nix.settings = {
    # 优先使用南大镜像
    substituters = [
      "https://mirrors.nju.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"    # 备用官方源
    ];

    #信任的镜像源
    trusted-substituters = [
      "https://mirrors.nju.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];
  };
}