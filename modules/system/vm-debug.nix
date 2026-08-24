# ============================================================
# VM 调试模块（默认关闭，仅供测试系统用）
#
# 使用方法：
#   1. 在 configuration.nix 的 imports 中取消注释本模块：
#        ./modules/system/vm-debug.nix
#   2. 构建并启动 VM：
#        sudo nixos-rebuild build-vm --flake /etc/nixos#reimilia
#        ./result/bin/run-reimilia-vm
#      （graphics=false 时已自动无头运行，启动日志直接输出到当前终端；
#       看到 "reimilia login:" 即表示系统启动成功）
#
# ⚠️ 新旧写法说明（重要）：
# - 新写法（nixpkgs >= 26.11）：qemu-vm 模块已从默认模块列表移除，
#   VM 相关选项必须写在 virtualisation.vmVariant 子模块中！
#   直接写在顶层会报错：
#     error: The option `virtualisation.qemu.options' does not exist.
# - 旧写法（nixpkgs <= 26.05）：qemu-vm 模块还在默认列表里，
#   以下选项直接写在顶层即可。
# 本仓库当前锁定的 nixpkgs 是 26.11 预发布（2026-08-05），默认启用新写法。
# ============================================================
{ config, lib, pkgs, ... }:

{
  # ---------- 新写法（nixpkgs >= 26.11，当前默认启用） ----------
  virtualisation.vmVariant = {
    # 无头启动：串口输出日志 + 跳过图形目标直达多用户登录
    boot.kernelParams = [ "console=ttyS0" "systemd.unit=multi-user.target" ];
    virtualisation.graphics = false;
  };

  # ---------- 旧写法（nixpkgs <= 26.05，仅供对比参考，启用会报错） ----------
  # 旧版在顶层直接写：
  #   boot.kernelParams = [ "console=ttyS0" "systemd.unit=multi-user.target" ];
  #   virtualisation.graphics = false;
  # 更早的 nixpkgs 则用：
  #   virtualisation.qemu.options = [ "-nographic" ];
}
