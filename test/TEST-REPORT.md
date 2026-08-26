# UTNixOS_Pro 容器测试报告

> 目的：在容器中搭建测试环境，验证 **两种安装方式**（curl 脚本 / git clone 本地）都能正常运行，
> 并验证 **Web 管理面板（WebUI）** 的所有主要功能正常。

## 测试环境

| 项目 | 值 |
| --- | --- |
| 宿主机 | CachyOS（Arch 系） |
| 容器运行时 | Docker 29.7.2（无 KVM） |
| 测试镜像 | `golang:1.22`（构建 webui）、`debian:bookworm`（跑脚本/WebUI 测试，本地缓存为 `utnixos-test:local`） |
| 仓库 | `/home/reimilia/UTNixOS`（已推送 GitHub `Reimilia617/UTNixOS_Pro`） |
| 测试脚本 | `test/script-test.sh`、`test/install-methods-test.sh`、`test/webui-test.sh`、`test/container-test.sh` |

## 测试方式说明

- 脚本/安装流程测试在 Debian 容器中用 **stub** 代替 `nixos-generate-config / nixos-install / nixos-rebuild / nix-env`，
  只记录调用参数，不真正构建系统；`/mnt` 以 tmpfs 模拟 live 安装挂载点。
- 交互菜单通过 `script`（util-linux）分配 PTY 驱动（`read` 需要 `/dev/tty`）。
- WebUI 测试启动真实编译出的 `webui` 二进制，用系统用户做 PAM 认证，`curl` 逐一验证全部 API。

## 一、两种安装方式验证

### 方式 A：curl 脚本安装（`curl <raw install.sh> | bash`）

等价路径：只把 `install.sh` 放到独立目录（旁边没有 `script/` 模块）→ 触发 **引导模式**，
脚本自动从 `GIT_URL` 拉取完整仓库再继续安装。

结果：**PASS（8/8）**

- `curl|bash` 触发引导模式（从 GIT_URL 拉取代码） ✓
- `configuration.nix` 部署到 `/mnt/etc/nixos` ✓
- `.utnixos-pro-selection` 选择状态生成 ✓
- `hardware-configuration.nix` 生成 ✓
- `script/` 模块随配置部署 ✓
- 桌面默认 xfce 启用 ✓
- `nixos-install --flake /mnt/etc/nixos#reimilia` 调用 ✓
- `nixos-generate-config --root /mnt` 调用 ✓

### 方式 B：git clone 到本地后安装

`git clone <repo> /tmp/methodB && bash /tmp/methodB/install.sh install`

结果：**PASS（6/6）**

- `git clone` 成功（install.sh 存在） ✓
- 使用克隆目录内 `script/` 模块（未走引导模式） ✓
- `configuration.nix` 部署 ✓
- `.utnixos-pro-selection` 生成 ✓
- `hardware-configuration.nix` 生成 ✓
- `nixos-install --flake` 调用 ✓
- 部署时保留 `.git`（供后续 update） ✓

### 补充：curl|bash 引导模式保险回滚（`--rollback`）

- `curl|bash --rollback` 保险回滚可用 ✓

## 二、脚本功能完整测试（script-test）

覆盖 install.sh 的 6 大命令，**PASS=54 FAIL=0**

1. `install.sh install`（默认选项，全默认模块）
2. `install.sh install`（自定义：gnome/systemd-boot/zh_CN/fcitx5/tuna/fish/webui/secrets）
3. `install.sh menu`（已装系统换模块 kde + 重建）
4. `install.sh update`（同步代码 + 保留机器文件 + 重放选择 + 重建）
5. `install.sh rollback`（回滚到指定 generation / 默认回滚分支）
6. 引导模式（curl|bash 等价，从 GIT_URL 拉取模块 + `--rollback`）

## 三、Web 管理面板（WebUI）全功能测试

**PASS=34 FAIL=0**，覆盖所有主要功能：

| 类别 | 覆盖点 |
| --- | --- |
| 健康/前端 | `/api/health`、`GET /` 页面、`/app.js` |
| 认证/安全 | PAM 正确密码登录、错误密码 401、禁止 root 403、无 cookie 401、跨站 POST 403、登录限速 429 |
| 状态/模块 | flake 配置识别、模块结构读取、`modules/apply` 切换模块 + 写 `.utnixos-pro-selection`（与 TUI 共用） |
| 软件包 | 声明式包读取、添加 `ripgrep` 写入 `host/packages.nix`、非法包名 400、属性校验 |
| 回滚 | generations 列表解析（3 条 current=21） |
| 审计 | 登录审计日志写入 `/var/lib/utnixos-pro-webui/audit.log` |
| 后台任务 | rebuild 任务启动 + SSE 流（status / line 事件） |
| 日志 | `journalctl` 查看、服务单元列表 |

## 四、构建与单元测试

- `go build ./cmd/webui`：成功（产物 `webui`，ELF x86-64 8.3MB）
- `go test ./...`：通过（`internal/config` ok）

## 五、结论

- ✅ **curl 脚本安装** 与 **git clone 本地安装** 两种方式均能正常运行完整安装流程。
- ✅ **Web 管理面板** 所有主要功能正常（登录、模块、软件包、回滚、审计、任务、日志、安全）。
- ✅ 脚本 6 大命令、Go 单元测试全部通过。

## 本次改动文件

- `test/script-test.sh` — 修复 PTY 交互输入驱动（逐行延时喂入），修复容器 git safe.directory
- `test/install-methods-test.sh` — 新增：明确验证 curl|bash 与 git clone 两种安装方式
- `test/webui-test.sh` — 修复 `modules/apply` 请求 JSON 结构（需嵌套在 `selection` 下，与前端一致）
- `test/result/*.log` — 本次测试运行日志
