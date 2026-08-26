// UTNixOS_Pro Web 管理面板入口。
//
// 安全模型：
//   - 默认仅监听 127.0.0.1（--addr 可配），不向防火墙开放任何端口；
//   - 登录使用系统用户/密码（PAM，通过 pamtester 调用，无 cgo）；
//   - 允许登录的用户组可配置（默认 wheel）；
//   - 所有 nix 命令均以参数数组方式执行（无 shell 拼接），输入全量校验。
package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"utnixos-pro.dev/webui/internal/server"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8090", "监听地址（默认仅本机，请勿暴露公网）")
	configDir := flag.String("config-dir", "/etc/nixos", "NixOS 配置目录")
	stateDir := flag.String("state-dir", "/var/lib/utnixos-pro-webui", "状态/审计日志目录")
	pamService := flag.String("pam-service", "utnixos-pro-webui", "PAM 服务名（对应 security.pam.services.<name>）")
	allowedGroup := flag.String("allowed-group", "wheel", "允许登录的管理员组，留空=任意系统用户")
	flag.Parse()

	srv, err := server.New(server.Options{
		Addr:         *addr,
		ConfigDir:    *configDir,
		StateDir:     *stateDir,
		PAMService:   *pamService,
		AllowedGroup: *allowedGroup,
		SessionTTL:   8 * time.Hour,
	})
	if err != nil {
		log.Fatalf("初始化失败: %v", err)
	}

	log.Printf("UTNixOS_Pro Web 管理面板监听 %s（配置目录 %s）", *addr, *configDir)
	log.Printf("登录认证: PAM 服务 %q, 允许组 %q", *pamService, *allowedGroup)
	if err := http.ListenAndServe(*addr, srv.Routes()); err != nil {
		log.Fatal(err)
	}
}
