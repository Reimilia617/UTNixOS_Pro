{ lib, buildGoModule }:

# UTNixOS Web 管理面板
# 纯 Go + 标准库实现（零第三方依赖），PAM 认证通过外部 pamtester 完成，
# 因此可静态编译，buildGoModule 无需 vendor。
buildGoModule {
  pname = "utnixos-webui";
  version = "0.1.0";

  src = ./.;

  # 无第三方 Go 依赖，不需要 vendorHash
  vendorHash = null;

  # 注意：不要在这里写 CGO_ENABLED = 0；buildGoModule 内部已在 env 里设置 CGO_ENABLED，
  # 顶层再传会被判为「env 与 derivation 参数重叠」导致求值失败：
  #   error: The `env` attribute set cannot contain any attributes passed to derivation.
  # 本程序是纯 Go 标准库实现，不 import cgo 包，go 会直接产出静态二进制，无需显式关闭。
  # checkPhase 的 go test 依赖仓库根目录的 configuration.nix/modules/（沙箱 src 只有 webui/），
  # 故关闭 checkPhase；测试可在仓库内用 `go test ./...` 手动运行。
  doCheck = false;

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "UTNixOS Web 管理面板（系统用户名/密码认证，仅本机访问）";
    homepage = "https://github.com/Reimilia617/UTNixOS";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
