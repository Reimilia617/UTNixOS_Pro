# UTNixOS_Pro Overlays 入口
#
# 用途：自定义/覆盖 nixpkgs 包，或添加自建包。
# 返回一个 overlay 列表（可以是空列表 []）。
#
# 示例：给某个包打补丁
#   (final: prev: {
#     # 覆盖 firefox 的版本/补丁
#     firefox = prev.firefox.overrideAttrs (old: {
#       patches = (old.patches or [ ]) ++ [ ./my-firefox.patch ];
#     });
#   })
#
# 示例：添加自建包（把包目录放在 packages/ 下）
#   (final: prev: {
#     my-package = final.callPackage ./packages/my-package { };
#   })
#
# 多个 overlay 就按顺序列出：
#   [
#     (import ./overlay1.nix)
#     (import ./overlay2.nix)
#   ]

[
  # UTNixOS_Pro Web 管理面板（自建包，见 webui/ 目录，由 modules/system/webui.nix 使用）
  (final: prev: {
    "utnixos-pro-webui" = final.callPackage ../webui { };
  })
]
