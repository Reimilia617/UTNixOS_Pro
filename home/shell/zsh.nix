{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" ];
    };

    # 注意：initExtra 已被 home-manager 弃用，这里统一使用 initContent
    initContent = ''
      # 关闭 P10K 首次配置向导（否则新用户第一次开终端会被交互式向导卡住）
      # 想自定义 P10K 外观：运行 p10k configure 生成 ~/.p10k.zsh 后自动加载
      export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

      # Load Themes
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      
      # 开机名言
      if command -v fortune > /dev/null; then
        echo
        fortune
         echo
      fi

    # 加载P10K配置文件,使用OhMyZSH
    [ -f ~/.p10k.zsh ] && source ~/.p10k.zsh

    '';
  };

  home.packages = with pkgs; [
    fortune
    cowsay
    zsh-powerlevel10k
    meslo-lgs-nf
  ];
}