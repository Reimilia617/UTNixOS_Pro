# sops-nix 密钥管理模板（默认关闭）
#
# 作用：把 WiFi 密码、API Token、SSH 密钥等敏感内容加密后放进仓库，
#       部署时自动解密到 /run/secrets/。
#
# 启用步骤：
#   1. 生成 age 密钥：  mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt
#   2. 创建 .sops.yaml（仓库根目录）：
#        creation_rules:
#          - age: <第1步输出的公钥>
#   3. 创建 secrets.yaml 并用 sops 加密：  sops secrets.yaml
#   4. 在 configuration.nix 中取消注释本模块，并取消下面配置的注释
#   5. 部署后 /run/secrets/<名字> 就是解密后的明文
#
# 注意：sops-nix 模块已在 flake.nix 中导入，这里只负责具体配置。
{ config, lib, pkgs, ... }:

{
  # sops.defaultSopsFile = ../secrets.yaml;
  # sops.age.keyFile = "/home/reimilia/.config/sops/age/keys.txt";
  #
  # sops.secrets."wifi-password" = { };
  # sops.secrets."github-token" = { };
  #
  # 使用示例（在需要密钥的模块里）：
  #   networking.wireless.networks."MyWiFi".psk = "file:///run/secrets/wifi-password";
}
