{
  description = "UTNixOS - Reimilia NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ---- 进阶模块（默认全部处于"未启用"状态，按需开启，见 README） ----
    # 密钥管理：sops-nix（配合 age 密钥加密敏感配置）
    sops-nix.url = "github:Mic92/sops-nix";
    # 声明式分区：disko
    disko.url = "github:nix-community/disko";
    # 根文件系统不持久化：impermanence
    impermanence.url = "github:nix-community/impermanence";
    # 常见硬件配置集：nixos-hardware（笔记本等按需引用）
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, impermanence, nixos-hardware, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # 主机列表：新增一台机器时在这里加一行即可
    # （注意：每台机器的 hardware-configuration.nix 需要在对应目录中单独生成）
    hosts = [ "reimilia" ];

    # 所有主机共享的模块
    # （sops/disko/impermanence 模块本身是惰性的，不配置对应选项就不会生效）
    baseModules = [
      ./configuration.nix
      home-manager.nixosModules.home-manager
      sops-nix.nixosModules.sops
      disko.nixosModules.disko
      impermanence.nixosModules.impermanence
      # 自定义包/覆盖包入口：见 overlays/default.nix
      { nixpkgs.overlays = import ./overlays/default.nix; }
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.reimilia = import ./home/home-manager.nix;
      }
    ];

    mkSystem = host: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = baseModules;
    };
  in
  {
    nixosConfigurations = builtins.listToAttrs (map (host: {
      name = host;
      value = mkSystem host;
    }) hosts);

    # 可单独构建的包：nix build .#webui
    packages.${system} = {
      webui = pkgs.callPackage ./webui { };
    };

    # 代码格式化：nix fmt
    # （treefmt 本身不打包格式化器，这里把 nixfmt 加进 PATH 再调用）
    formatter.${system} = pkgs.writeShellScriptBin "utnixos-fmt" ''
      export PATH="${nixpkgs.lib.makeBinPath [ pkgs.treefmt pkgs.nixfmt ]}:$PATH"
      exec ${pkgs.treefmt}/bin/treefmt "$@"
    '';

    # 开发环境：格式化/静态检查工具
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        treefmt
        nixfmt
        statix
        deadnix
      ];
    };

    # 检查（nix flake check 会构建并运行这里的所有 check）
    # 注意：boot 是 KVM 启动冒烟测试，比较重；只想快速评测可用 nix flake check --no-build
    checks.${system} = {
      boot = pkgs.testers.runNixOSTest (import ./nixos-tests/boot.nix {
        inherit home-manager;
      });
    };
  };
}


#空に踊る緋色月 鮮やかに揺らめいた
#空中跳动着的绯色之月 鲜艳地摇曳着

#瞳を刺すその色が 私を狂わせ…
#刺痛瞳孔的色彩 让我变得疯狂起来…

#デストロオオオオオオオオイ!!!!!!!!
#DESTROOOOOOOOY！！！！！！！！

#マスパした！！！
#MASTER SPARK！！！

#私のニューロサーキットがマスタースパークした！！
#我的神经回路发射出MASTER SPARK了！！

#そしていま全て理解した！
#于是我完全明白了！

#理解していないことを理解した！
#不明白的也变得明白了！

#そんな私のツバサのコスモから ラーメンライスがほとばしる
#从我的双翼的小宇宙 还有拉面和米饭里喷薄出来了

#あー！これはもう、ようするに
#啊~！这就是、就是说

#ようするに、なんていうか、なんなんだああああああああ！！！
#就是说、怎么说呢、究竟是什么啊啊啊啊啊啊啊啊！！！

#フゥーハハァ！よくきたな魔理沙と霊梦このやろう！！
#呜啊！魔理沙灵梦你们两个混蛋来的正好！！

#なんかのキノコと100円やるからカエレこのやろう！！
#给你们不知道哪儿来的蘑菇和100円回去吧！！

#あ、帰った！安い！安いぞ主人公！！！
#啊、走了！好廉价啊！廉价的主人公啊！

#よっしゃー！とりあえず暇だから適当にうたうぞおお！！
#耶~！总之很闲 那么就来唱唱歌吧！！
