{ config, lib, pkgs, ... }: {
    system.autoUpgrade = {
        enable = true;
        allowReboot = false;
        flake = "/etc/nixos";
        flags = [
            # 同时更新 nixpkgs 和 home-manager 两个 input，避免 home-manager
            # 长期锁在旧版本导致与新 nixpkgs 不兼容
            "--update-input" "nixpkgs"
            "--update-input" "home-manager"
            # 自动更新时使用与系统一致的镜像源（跟随 modules/mirrors/*.nix）
            "--option" "substituters" (lib.concatStringsSep " " config.nix.settings.substituters)
        ];
        dates = "03:00";     # AM3:00 Auto Update
        randomizedDelaySec = "45min";
    };
}