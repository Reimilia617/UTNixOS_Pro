{ config, pkgs, ... }:

{
  users.users.reimilia = {
    isNormalUser = true;
    description = "Reimilia";
    # shell 由 modules/shell/*.nix 统一设置（默认 zsh，可用 install.sh 换成 bash/fish），
    # 这里不再单独指定，避免覆盖 users.defaultUserShell

    extraGroups = [
      "wheel"     # Sudo
      "networkmanager"     # Network
      "video"     # video/display
      "audio"     # audio
      "input"     # inputmethod
      "bluetooth"     # Bluetooth
    ];

    # TempPassword(Please run "passwd" in the termimal after first login)
    # 以哈希形式存储临时密码（避免明文出现在公开仓库中），
    # 生成方式：openssl passwd -6 123456
    initialHashedPassword = "$6$kD9mMW0kEEjXfxxa$yMt2YYU0zrViqgX07YbLuDK8ISfb4sGI61TQ.5EdQsKKTbqdYPq.2uLO6chfdcKfa6GnUTW/UIer5jGxThL0C.";

    # Or use hashedPassword(Safety):
    #hashedPassword = "";     # use mkpasswd -m sha512crypt
  };

  # sudo: wheel need password
  security.sudo.wheelNeedsPassword = true;
}