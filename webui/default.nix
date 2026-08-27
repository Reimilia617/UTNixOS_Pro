{ lib, buildGoModule }:

# UTNixOS_Pro Web 管理面板
# 纯 Go + 标准库实现（零第三方依赖），PAM 认证通过外部 pamtester 完成，
# 因此可静态编译，buildGoModule 无需 vendor。
buildGoModule {
  pname = "utnixos-pro-webui";
  version = "0.1.0";

  src = ./.;

  # main 包在 cmd/webui：buildGoModule 默认只构建模块根目录（.），根目录没有
  # main 包会导致 `go install .` 报「no Go files」构建失败，必须显式声明子包。
  # 注意：不要在这里用 installPhase 覆盖 + `cd "${modRoot}"` —— modRoot 是
  # buildGoModule 内部参数，不在本 derivation 作用域里，会直接求值报错
  # （undefined variable `modRoot`）。
  subPackages = [ "./cmd/webui" ];

  # 产物名保险：不同 nixpkgs 版本对子包产物的命名不同（有的按 pname 命名，
  # 有的按子包名），postInstall 统一确保存在 $out/bin/webui，
  # 与 modules/system/webui.nix 的 ExecStart（${package}/bin/webui）对齐。
  # 注意：这里不能写 "${pname}"——pname 只是本 attrset 的属性名，不是作用域
  # 变量，插值会报 undefined variable `pname`（与之前的 modRoot 同款错误）。
  postInstall = ''
    if [[ ! -x "$out/bin/webui" ]]; then
      mv -f "$out/bin/utnixos-pro-webui" "$out/bin/webui" 2>/dev/null || true
    fi
  '';

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
    description = "UTNixOS_Pro Web 管理面板（系统用户名/密码认证，仅本机访问）";
    homepage = "https://github.com/Reimilia617/UTNixOS_Pro";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
