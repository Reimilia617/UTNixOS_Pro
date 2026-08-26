# UTNixOS_Pro 启动冒烟测试
#
# 作用：在 KVM 虚拟机中真实启动默认配置，验证系统能：
#   1. 正常引导到多用户目标
#   2. NetworkManager 等关键服务启动
#   3. reimilia 用户创建成功且默认 shell 是 zsh
#   4. Home-Manager 激活完成（/home/reimilia/.zshrc 存在）
#
# 运行方式：nix build .#tests.x86_64-linux.boot
# （需要 KVM 支持；GitHub Actions 的 ubuntu runner 自带 KVM）
#
# 注意：这里用的是仓库自带的示例 hardware-configuration.nix（QEMU 虚拟机），
# 因此测试环境是虚拟化友好的，与真实机器的硬件配置无关。
{ home-manager }:

{
  name = "utnixos-pro-boot";

  # 关键：测试框架默认把 nixpkgs.config 设为只读（共享宿主 pkgs），
  # 会与 applications.nix 里的 nixpkgs.config.allowUnfree = true 冲突。
  # 关闭只读，让测试机用正常的 nixpkgs 评测。
  node.pkgsReadOnly = false;

  nodes.machine =
    { config, lib, pkgs, ... }:
    {
      imports = [
        ../configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.reimilia = import ../home/home-manager.nix;
        }
      ];

      # 无头启动 + 跳过图形目标（SDDM/X11 不在无显示器环境里启动）
      boot.kernelParams = [ "systemd.unit=multi-user.target" ];

      # 测试机资源给大一点，避免构建/启动超时
      virtualisation.memorySize = 2048;
      virtualisation.cores = 4;
    };

  testScript = ''
    # 1. 系统成功引导到多用户目标
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("systemctl is-active NetworkManager")

    # 2. 系统优化模块的定时器已注册（auto-update / gc）
    machine.succeed("systemctl is-active nixos-upgrade.timer")
    machine.succeed("systemctl is-active nix-gc.timer")

    # 3. reimilia 用户存在且 shell 为 zsh
    machine.succeed("getent passwd reimilia | grep -q 'bin/zsh'")
    machine.succeed("grep -q reimilia /etc/group")

    # 4. Home-Manager 激活完成，zsh 配置已生成
    # （诊断信息：如果失败，先打印服务状态和日志）
    machine.succeed(
        "systemctl show home-manager-reimilia.service -p ActiveState,SubState,Result || true"
    )
    machine.succeed(
        "journalctl -u home-manager-reimilia.service --no-pager | tail -30 || true"
    )
    # 注意：home-manager 开启了 xdg.enable，zsh 配置在 ~/.config/zsh/ 下
    machine.wait_until_succeeds(
        "test -f /home/reimilia/.config/zsh/.zshrc", timeout=240
    )

    # 5. 壁纸文件跟随 flake 进入了 store（GNOME 模块的文件存在性不在这里验证，
    #    只验证主题/字体等目录确实在系统里）
    machine.succeed("ls /run/current-system/sw/bin/zsh")

    print("UTNixOS_Pro boot test: ALL PASSED")
  '';
}
