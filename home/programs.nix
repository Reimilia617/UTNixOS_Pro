{ pkgs, ... }:

{
  # 常用程序的声明式配置（比只装包更干净，配置随系统同步/换机不丢）

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Reimilia";
        email = "3568400373@qq.com";     # TODO: 改成你自己的邮箱
      };
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.ssh = {
    enable = true;
    # 显式关闭默认配置注入，消除 home-manager 弃用警告：
    #   "programs.ssh default values will be removed in the future"
    # （需要默认值时手动在 settings."*" 里写）
    enableDefaultConfig = false;
    # 管理信任主机：~/.ssh/known_hosts 由 home-manager 接管后可在这里加
    # extraConfig = { Host "github.com" = { User = "git"; }; };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.bat.enable = true;
  programs.htop.enable = true;
}
