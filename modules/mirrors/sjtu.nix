{ config, pkgs, ... }:

{
  # 上海交大镜像源
  nix.settings = {
    # 优先使用交大镜像
    substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"    # 备用官方源
    ];

    #信任的镜像源
    trusted-substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];
  };
}
