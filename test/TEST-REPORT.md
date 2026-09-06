# UTNixOS_Pro 容器测试说明

> 目的：在容器中搭建测试环境，验证 install.sh（单文件：安装 / 修复配置 / UT紧急回滚）
> 与 Web 管理面板（内置 systemd 守护进程）的主要功能。
>
> 运行：`bash test/container-test.sh`（宿主机需要 docker；Go 构建步骤在 golang 容器内完成）。
> 每次运行的日志保存在 `test/result/`。

## 测试环境

| 项目 | 值 |
| --- | --- |
| 容器运行时 | Docker |
| 测试镜像 | `golang:1.22`（构建 webui）、`debian:bookworm`（跑脚本/WebUI 测试） |
| 测试脚本 | `test/script-test.sh`、`test/webui-test.sh`、`test/container-test.sh`（另：`test/install-methods-test.sh` 可单独跑两种安装方式） |

## 测试方式说明

- 脚本/安装流程测试在 Debian 容器中用 **stub** 代替 `nixos-generate-config / nixos-install /
  nixos-rebuild / nix-env`，只记录调用参数，不真正构建系统；`/mnt` 以 tmpfs 模拟 live 安装挂载点。
- 交互菜单通过 `script`（util-linux）分配 PTY 驱动（`read` 需要 `/dev/tty`）。
- WebUI 测试启动真实编译出的 `webui` 二进制，用系统用户做 PAM 认证，`curl` 逐一验证全部 API。

## 一、install.sh 功能测试（script-test）

覆盖（去 Bash 脚本化后的单文件 install.sh，无 `script/` 目录）：

1. `help` 中英双语 + `TERM=linux`（虚拟控制台）强制英文（避免中文方块）
2. `install.sh install`（默认选项全新安装：配置部署 / webui·ut 内置导入启用 /
   状态文件不含 webui / nixos-install 以 flake+镜像源调用）
3. `install.sh install`（自定义：systemd-boot/gnome/zh_CN/fcitx5/tuna/fish/vm-debug/secrets）
4. `install.sh install`（GRUB BIOS + 主题 + 目标磁盘写入 host/grub-device.nix）
5. 入口菜单（已装系统）：进入脚本可选 全新安装 / 修复配置 / UT紧急回滚，含 `ut` 提示；
   选 3 进入 UT紧急回滚
6. `install.sh repair`：/etc/nixos 损坏时修复（保留机器文件、恢复 flake.nix/install.sh、
   重放选择、触发重建、生成备份目录）；stdin 形式（`bash -s -- repair`）
7. `install.sh rollback`：回滚到指定 generation / 回车默认回滚到上一版本，标题「UT紧急回滚」
8. 自包含：把 install.sh 单文件放到独立目录即可 `--rollback`（无需拉取仓库）

## 二、两种安装方式（install-methods-test，可单独运行）

- 方式 A（curl|bash 等价）：只有 install.sh 单文件 → 安装时自动从 GIT_URL 拉取完整仓库
- 方式 B：git clone 到本地 → 直接复用克隆目录
- 补充：单文件 `--rollback` 应急回滚（标题 UT紧急回滚）

## 三、Web 管理面板（WebUI）全功能测试

覆盖：

| 类别 | 覆盖点 |
| --- | --- |
| 健康/前端 | `/api/health`、`GET /` 页面、`/app.js` |
| 认证/安全 | PAM 正确密码登录、错误密码 401、禁止 root 403、无 cookie 401、跨站 POST 403、登录限速 429 |
| 状态/模块 | flake 配置识别、模块结构读取（webui 已内置，不在可选/其他列表）、
  `modules/apply` 切换模块并写 `.utnixos-pro-selection`（webui 历史值被清洗、内置导入保持启用） |
| 软件包 | 声明式包读取、添加 `ripgrep` 写入 `host/packages.nix`、非法包名 400、属性校验 |
| 回滚 | generations 列表解析 |
| 审计 | 审计日志写入 `/var/lib/utnixos-pro-webui/audit.log` |
| 后台任务 | rebuild 任务启动 + SSE 流 |
| 日志 | `journalctl` 查看、服务单元列表 |

## 四、构建与单元测试

- `go build ./cmd/webui`（golang 容器）
- `go test ./...`（`internal/config` 等）
- KVM 启动冒烟测试由 CI（`nix flake check`）执行，含：面板服务健康检查、`webui`/`ut` 二进制、
  无头环境下 `ut` 打印面板地址
