{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # 终端工具
    bat
    tree
    htop
    lolcat
    cowsay
    fortune

    # 轻量脚本语言（常用，保留）
    python3

    # ---- 编译器工具链默认不再全局安装（太重，每个用户 profile 都背一套）----
    # 推荐做法：
    #  1. 按项目使用 nix develop / devShells（flake 里定义）
    #  2. 或临时进入：nix shell nixpkgs#gcc nixpkgs#rustc
    # 如确实需要全局安装，取消下面注释：
    # rustc
    # cargo
    # gcc
    # gnumake
    # cmake
  ];
}