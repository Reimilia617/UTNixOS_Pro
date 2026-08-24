{ config, pkgs, ... }:

{
  # 清华镜像源
  nix.settings = {
    # 优先使用清华源镜像
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"    # 备用官方源
    ];

    #信任的镜像源
    trusted-substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];
  };
}