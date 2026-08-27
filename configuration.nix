{ config, pkgs, ... }:

{
  # Modules
  imports = [
    # Hardware
    ./hardware-configuration.nix

    # System Plugins
    ./modules/system/auto-update.nix     # AUTO-Update
    ./modules/system/clean.nix     # AUTO-Clean-Rubbish
    ./modules/system/nix-command.nix     # Advanced package manager
    ./modules/system/zram.nix     # Memory ZSTD
    ./modules/system/fonts.nix     # Fonts(默认启用)
    ./modules/system/ut.nix     # ut命令(UTNixOS_Pro管理接口)
    ./modules/system/webui.nix     # Web管理面板(默认启用,http://127.0.0.1:8090)
    #./modules/system/nopwdtodesktop.nix     # Auto Login
    #./modules/system/vm-debug.nix     # VM调试(无头启动,默认关闭,见文件内说明)
    #./modules/system/secrets.nix     # sops-nix密钥管理(模板,默认关闭)
    #./modules/system/impermanence.nix     # 根分区不持久化(模板,默认关闭)
    #./modules/system/backup.nix     # restic定时备份(模板,默认关闭)
    #./modules/system/security.nix     # fail2ban安全(模板,默认关闭)

    # Bootloader（用 `ut menu` / 安装菜单选择，GRUB 可选主题）
    ./modules/boot/grub.nix     # GRUB(UEFI)
    #./modules/boot/grub-bios.nix     # GRUB(BIOS/传统启动,目标磁盘见 host/grub-device.nix)
    #./modules/boot/systemd-boot.nix     #systemd-boot(UEFI-Only)
    ./modules/boot/grub-theme.nix     # GRUB Themes(Reimu,可选)

    # Desktop
    #./modules/desktop/gnome.nix     #GNOME
    #./modules/desktop/kde.nix     #KDE Plasma
    ./modules/desktop/xfce.nix     #XFCE
    #./modules/desktop/lxqt.nix     #LXQT
    #./modules/desktop/hyprland.nix     #Hyprland
    #./modules/desktop/cosmic.nix     #COSMIC

    # Locale(English Default)
    ./modules/locale/en_US.nix     #English(US)
    #./modules/locale/zh_CN.nix     #中文(中国)

    # Input
    ./modules/input/ibus.nix     #IBus
    #./modules/input/fcitx5.nix     #Fcitx5

    # 设置系统级默认Shell（同一时间只启用一个）
    ./modules/shell/zsh.nix     #ZSH
    #./modules/shell/bash.nix     #Bash
    #./modules/shell/fish.nix     #Fish

    # Audio
    ./modules/audio/pipewire.nix

    # Bluetooth
    ./modules/bluetooth/bluetooth.nix

    # Users
    ./modules/users/reimilia.nix

    # Network
    ./modules/network/network.nix

    # Mirrors
    ./modules/mirrors/ustc.nix     #中科大
    #./modules/mirrors/tuna.nix     #清华
    #./modules/mirrors/nju.nix     #南京大

    # Packages
    ./modules/packages/applications.nix     # Base App

    # 机器本地文件（由 Web 管理面板自动维护，勿删除）
    ./host/packages.nix     # Web 面板安装的软件包
    ./host/grub-device.nix     # GRUB(BIOS) 引导设备(选中 grub-bios 时自动写入)
  ];

  # Firmware
  hardware.enableAllFirmware = true;

  # System Version
  system.stateVersion = "26.05";
  
}


#クッ…！こんな時にまで…！静まれッ…！
#呜咕…！这个时候还…！静一点…！

#ぐおおおおお！！私から離れろおおおお！！
#呜哦哦哦哦哦！！离我远一点啊啊啊啊！！

#そもそもゲームをする時は、部屋を明るくして離れるんだああ！！
#话说来 玩游戏的时候啊、要保持房间明亮而且离得远一点哦哦！！

#私は…私は… もう誰もきずつけたくないんべべぽーーー！！
#我啊…我啊… 其实谁也不想弄伤的啊啊啊——！！

#もうなにもかもがぐちゃどろー！
#已经不想发什么牢骚了~！

#捧げろげろ血の雫！ちゅるちゅるで！うまうまな！
#把滴滴鲜血都献上来吧！啾啾地！很美味吧！

#じゅるじゅるじゅる吸い尽くす！お腹が空いたからーっ！
#咻咻咻地吸光光！因为我肚子饿了嘛！

#捧げろげろその体！いろいろと！おいしそう！
#把身体献上来吧！各种各样的！似乎很美味！

#あんなコトや こんなコト！ ハァハァしやしゃんせー！
#这样的东西 那样的东西！ 满满地大开眼界啦！

#むっはーーーー！！
#姆哇~~~~！！

#ガイアが私にもっと輝きまくれと、囁きまくってる気がするじぇええ！！！
#盖亚让我更加光辉耀眼、在耳边挥之不去的低语我才不会在意呢！！！

#しかし、このままでは私のゲシュタレイションが崩壊ングしてしまう！！
#可是啊、这样下去我的形态就要崩坏了呀！！

#ゆんゆん電波降り注ぎングでサテラビュー来ちゃいまひゅううう！！
#需要Satellaview来注入强力的电波咯！！

#なぬっ！レーヴァテインうめえええ！！
#什么！LAVATEIN很好吃！！

#おねえさまあああ！！！そこのマヨネーズとってええええええええ！！！
#姐姐大人！！！怎么去拿那里的蛋黄酱了呀呀呀呀呀呀呀呀！！！

#Ｏｈ！Ｎｏ！塩じゃない！咲夜Ｎｏ！ペッパーじゃない！
#Oh！No！不要放盐！ 咲夜No！胡椒也不要放啊！

#ふしゅぅぅ… 壁殴っちまったじぇぇぇぇい…！！
#呜咻… 我要把墙壁打坏了呀…！！
