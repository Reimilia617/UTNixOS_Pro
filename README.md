# UTNixOS_Pro - Reimilia NixOS Configuration

```
##     ## ######## ##    ## #### ##     ##  #######   ######          ######## ########  ######
##     ##    ##    ###   ##  ##   ##   ##  ##     ## ##    ##          ##    ## ##    ## ##    ##
##     ##    ##    ####  ##  ##    ## ##   ##     ## ##          ##    ## ##    ## ##    ##
##     ##    ##    ## ## ##  ##     ###    ##     ##  ######          ######## ######## ##    ##
##     ##    ##    ##  ####  ##    ## ##   ##     ##       ##          ##       ##   ##  ##    ##
##     ##    ##    ##   ###  ##   ##   ##  ##     ## ##    ##          ##       ##  ##   ##    ##
 #######     ##    ##    ## #### ##     ##  #######   ###### ######## ##       ##   ##   ######
```

一个把 **NixOS** 从「装到哪算哪」变成「想要什么就在菜单里选一下」的个人配置。模块化、可回滚、多主机，外加一点点东方厨的浪漫。

- ⚠ **重要提示**：不要同时启用多个同类型的功能模块，会引起冲突！
- 提示：没啥可更新的了，直接变 LTS 长期(不)维护了 (o′┏▽┓┛o)
- 注意：写完这篇 README 的时候 NixOS 已经出到了 26.05，所有测试也都是基于 26.05 测试的！

---

## 目录

- [特性](#特性)
- [快速开始（交互式安装脚本）](#快速开始交互式安装脚本)
- [ut 命令：系统的管理总接口](#ut-命令系统的管理总接口)
- [系统回滚（保险方案）](#系统回滚保险方案)
- [手动安装](#手动安装不用脚本也行)
- [Flake 使用](#flake-使用)
- [常用模块速查](#常用模块速查)
- [进阶功能](#进阶功能模板默认关闭按需开启)
- [测试与 CI](#测试与-ci)
- [VM 调试](#vm调试构建虚拟机测试系统用)
- [彩蛋（Bad Apple!!）](#彩蛋bad-apple)
- [脚本结构](#脚本结构跟-nixos-配置一样是模块化的)
- [🙏 致谢与代码来源](#-致谢与代码来源)
- [👥 贡献者](#-贡献者)
- [更新日志](#更新日志)

---

# 特性~(￣▽￣)~*

- 默认 XFCE 桌面环境，可选 GNOME/KDE/LXQT/Hyprland/COSMIC
- IBus + Rime 输入法（可选 Fcitx5，KDE 用户推荐选 Fcitx5 呢）
- 将 ZSH 作为默认 SHELL（可选 Bash/Fish，用 `ut menu` 一键切换）
- Home-Manager 管理：Oh My ZSH + Powerlevel10K + 开机名言彩蛋 + 声明式配置(git/ssh/fzf)
- 使用 GRUB 作为引导加载器（UEFI / BIOS 传统启动可选；也可选 Systemd-boot，启动更快但不支持主题）
- 安装/更换引导时先选「GRUB(UEFI) / GRUB(BIOS) / systemd-boot」，选 GRUB 再问要不要东方主题（默认开）
- BIOS/MBR 启动时自动询问 GRUB 安装目标磁盘（如 /dev/sda），写入机器本地文件 `host/grub-device.nix`
- 默认全英文环境，可选为中文环境
- 模块化配置结构
- Flake + Home-Manager（XDG 目录规范 + git/ssh/fzf 声明式配置）
- 5 个系统优化模块：自动更新/自动清理/ZRAM 压缩/Flakes 实验特性/免密自动登录(默认关)
- 统一字体方案（Noto + Nerd Font，中英文通用）
- 交互式安装/更新脚本（install.sh）+ `ut` 系统管理命令
- CI + 虚拟机启动测试 + 代码格式化（treefmt/statix/deadnix）
- 多主机支持（flake 里加一行即可新增机器）
- 系统回滚（含 `curl --rollback` 保险方案）

---

# 快速开始（交互式安装脚本）ヾ(•ω•`)o

## 全新安装（NixOS live 环境）

1. 分区（推荐 UEFI+GPT）并格式化
2. 挂载分区：
   ```
   mount /dev/你的根分区 /mnt
   mount /dev/你的ESP分区 /mnt/boot      # UEFI：NixOS 默认 GRUB/systemd-boot 在 /boot 找 ESP
   # 或 mount /dev/你的boot分区 /mnt/boot # BIOS 老机器
   ```
   > ⚠ 注意：**不要**把 ESP 挂到 `/mnt/boot/efi`——那是 Ubuntu 等发行版的做法。
   > NixOS 的 GRUB/systemd-boot 默认 EFI 目录是 `/boot`（`boot.loader.efi.efiSysMountPoint`，
   > 默认值 `/boot`）。挂到 `/boot/efi` 会导致引导程序找不到 ESP 而安装失败；
   > 除非你在配置里显式设置 `boot.loader.efi.efiSysMountPoint = "/boot/efi"`。
   >
   > 💡 网络慢？装系统前先**导出代理环境变量**（脚本会自动把它传给 curl/git 和
   > `nixos-install` 的 store 下载，最耗时的闭包下载也走代理）：
   > ```
   > export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
   > # Clash 等代理还提供 SOCKS：export all_proxy=socks5://127.0.0.1:7891
   > curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | bash
   > ```
   > 注意：**必须用 export**（而不是给 curl 加 `-x`），否则引导器内部拉取代码
   > 的 git clone/curl 不走代理，会卡在 fetch 阶段。还嫌慢就加 `--no-apple`
   > （跳过下载 badapple.mp4 视频，fetch 快很多）：
   > ```
   > curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | bash -s -- --no-apple
   > ```
   > 同时装的时候在镜像源菜单里选个快的（中科大/清华）。
3. 一条命令弹出交互式菜单：
   ```
   curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | bash
   ```
   菜单里自由选择：引导加载器（GRUB/UEFI、GRUB/BIOS、systemd-boot，GRUB 会再问要不要主题，BIOS 还会问目标磁盘）/桌面环境/语言/输入法/镜像源/Shell/系统模块/进阶模块，
   脚本会自动修改 configuration.nix（和 home-manager.nix）、生成硬件配置、执行 `nixos-install` 部署系统。
4. 安装完成后 reboot，用 `reimilia / 123456` 登录，第一时间执行 `passwd` 修改密码！

### 中英双语（自动选择）

脚本（`install.sh` / `ut`）界面支持中英双语，启动时自动选择语言：

- **Linux 虚拟控制台（TTY1-6，`TERM=linux`）**：控制台位图字体通常不含中文字形，显示中文会变成
  方块字，因此默认使用**英文**。
- 其他终端：按 `LANG` / `LC_ALL` 自动检测（`zh*` → 中文，其余 → 英文）。

如需强制指定语言，可用环境变量覆盖：

```
UTNIXOS_PRO_LANG=zh  ut      # 强制中文
UTNIXOS_PRO_LANG=en  ut      # 强制英文（例如在无法显示中文的终端上）
```

## ut 命令：系统的管理总接口（安装后内置）

只要用了本配置，整个系统都由 `ut` 管理，想换什么就换：

```
ut                    # 打开管理面板（等价于 sudo install.sh）
```

管理面板提供：

- 1) 重建系统（nixos-rebuild switch）
- 2) 清理构建垃圾（nix-collect-garbage -d）
- 3) 选择/更换模块（桌面/引导/Shell/输入法等，自动改配置）
- 4) 更新配置（从 GitHub 同步最新代码 + 重建）
- 5) 更新 Flake（nix flake update 所有输入 + 重建）
- 6) 系统回滚（选择之前的 generation）

常用快捷方式：

```
ut update          # 更新配置（同步代码+重建）
ut menu            # 只换模块（比如换桌面/Shell）
ut rollback        # 系统回滚
ut repair          # 一键修复：/etc/nixos 坏了（缺 flake.nix/install.sh，ut 崩）时，
                   # 保留机器配置，拉取最新代码重建 /etc/nixos 并重建系统
```

> 修复入口不用记参数：管理面板菜单里有「7) 一键修复」；而且 `ut` 检测到
> `/etc/nixos` 损坏（缺 flake.nix）时会**自动进入修复**。

> 如果 `/etc/nixos` 坏到连 `ut` 都跑不了，直接用 curl 拉脚本修复（不需要 /etc/nixos 完好）：
>
> ```
> curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | sudo bash -s -- repair
> ```
>
> 修复会先全量备份 `/etc/nixos` 到 `/etc/nixos.repair-<时间戳>`，并保留
> `hardware-configuration.nix` / `host/packages.nix` / `host/grub-device.nix` / 模块选择状态。

---

# 系统回滚（保险方案）

- 常规回滚：`ut` → 选 6，或 `sudo bash install.sh rollback`
- **本地脚本/配置坏了也能回滚**：直接 curl 最新脚本加 `--rollback` 参数：
  ```
  curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | sudo bash -s -- --rollback
  ```
  回滚不依赖 /etc/nixos 里的配置，只操作系统 generations。

## 更新系统（不用 ut 也行）

```
sudo bash /etc/nixos/install.sh update     # 从GitHub同步最新代码 + 重建
```

---

# 手动安装（不用脚本也行）

1. 使用 cfdisk 分区（如果你喜欢用别的也可以）
   - ⚠ 提示：最好是 UEFI+GPT；若是只能 BIOS 启动，用 `ut menu` 选择「GRUB(BIOS)」并按提示输入目标磁盘
     （脚本会写入 `host/grub-device.nix` 的 `boot.loader.grub.device`，无需再手动改模块）
   - Tips: 如果你是 UEFI 启动可选择 Systemd-boot，启动速度更快，但是不支持主题
2. 格式化分区并挂载（UEFI 记得把 ESP 挂到 `/mnt/boot`，别挂 `/mnt/boot/efi`，见上方「全新安装」的注意事项）
3. 使用 `nixos-generate-config --root /mnt` 获取配置文件，配置文件存储在 `"/你挂载的目录/etc/nixos/"` 下
4. 使用 cp 命令替换除了 `hardware-configuration.nix` 外的所有文件
   - ⚠ 仓库自带的 `hardware-configuration.nix` 只是供评测/CI 用的【示例】（面向 QEMU 虚拟机），千万别直接用于真实机器！
5. 执行 `nixos-install` 开始安装！（若下载速度过慢可添加 `--option substituters "镜像地址+原地址"`）
6. 设置完 root 密码后输入 `reboot` 重启进入系统(❁´◡`❁)
7. 使用默认用户名: reimilia + 临时密码: 123456 登录，进入桌面第一时间打开终端输入 `passwd` 更改账户密码
   - （临时密码以哈希形式存储在配置里，登录后请立即修改！）

咲夜提醒您：经作者测试，可以使用以下命令加快 NixOS 在国内的下载速度

```
nixos-install --option substituters "https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org"
```

---

# Flake 使用

- 手动更新系统：`sudo nixos-rebuild switch --flake /etc/nixos#reimilia`（已内置为 sys-update 别名）
- 或者：`nixos-rebuild switch --flake github:Reimilia617/UTNixOS_Pro#reimilia`
- 多主机：新增机器时在 flake.nix 的 hosts 列表里加一行，并把对应 hardware-configuration.nix 放到机器上
- 格式化代码：`nix fmt`（检查是否有未格式化文件：`nix fmt -- --fail-on-change`）
- 开发环境（treefmt/nixfmt/statix/deadnix）：`nix develop`

---

# 常用模块速查

- 桌面：`modules/desktop/*.nix`（默认 xfce，其他取消注释即可切换）
- 引导：`modules/boot/{grub,grub-bios,systemd-boot}.nix`（GRUB 主题 `grub-theme.nix` 可选；BIOS 目标磁盘在 `host/grub-device.nix`）
- 输入法：`modules/input/{ibus,fcitx5}.nix`
- 语言：`modules/locale/{en_US,zh_CN}.nix`
- 镜像：`modules/mirrors/{ustc,tuna,nju,sjtu}.nix`（中科大 / 清华 / 南大 / 上海交大）
- 系统优化：`modules/system/*.nix`（auto-update/clean/zram/nix-command/fonts/nopwdtodesktop/vm-debug）

---

# 进阶功能（模板默认关闭，按需开启）

- 密钥管理（sops-nix）：`modules/system/secrets.nix` —— WiFi 密码/Token 加密进仓库，见文件内步骤
- 根分区不持久化（impermanence）：`modules/system/impermanence.nix` —— 重启还原系统，见文件内警告
- 定时备份（restic）：`modules/system/backup.nix` —— 每日备份目录到远程仓库
- 安全（fail2ban）：`modules/system/security.nix` —— 自动封禁暴力破解 IP
- 声明式分区（disko）：`disko-config.nix` —— 用配置替代 cfdisk 分区
- 自定义包（overlays）：`overlays/default.nix` —— 覆盖/添加 nixpkgs 包
- 笔记本硬件优化：flake 里已引入 nixos-hardware，用法示例：
  ```
  # 在 configuration.nix 的 imports 中加入（以联想 ThinkPad 为例）：
  # imports = [ (modulesPath + "/profiles/hardware.nix") ]  # 或者引用 nixos-hardware 的模块
  ```
- 无头虚拟机调试：`modules/system/vm-debug.nix`（见下方「VM 调试」）

---

# 测试与 CI

- 完整检查（评测 + KVM 启动冒烟测试，比较重）：
  ```
  nix flake check
  ```
- 只想快速评测（不构建/运行测试）：
  ```
  nix flake check --no-build
  ```
- 单独运行启动冒烟测试（真实开虚拟机，需要 KVM）：
  ```
  nix build .#checks.x86_64-linux.boot
  ```
- GitHub Actions 已配置好 CI（.github/workflows/ci.yml）：
  - push 时自动跑 flake check + statix/deadnix + `nix fmt --check`
  - 以及 KVM 启动冒烟测试（ubuntu runner 自带 KVM）

---

# VM调试（构建虚拟机测试系统用）

1. 在 configuration.nix 的 imports 中取消注释：`./modules/system/vm-debug.nix`
2. 构建：`sudo nixos-rebuild build-vm --flake /etc/nixos#reimilia`
3. 启动：`./result/bin/run-reimilia-vm`（已无头运行，串口日志直接打印到终端，看到 `reimilia login:` 即启动成功）
   - ⚠ 注意新旧写法差异（见 `modules/system/vm-debug.nix` 内注释）：
     - nixpkgs >= 26.11：VM 选项必须写在 `virtualisation.vmVariant` 子模块里
     - nixpkgs <= 26.05：直接写在顶层（`virtualisation.graphics=false` / `virtualisation.qemu.options=["-nographic"]`）
     - 写错层级会报 `The option virtualisation.qemu.options' does not exist`

---

# 彩蛋（Bad Apple!!）

在**模块选择界面**（`ut menu` / 安装时的选择菜单）输入 `touhou` 回车，
会播放 `media/badapple.mp4`（東方萃夢想 · Bad Apple!! 影绘）。

- 大小写不限（touhou / Touhou / TOUHOU!!! 都行）
- 会自动挑选播放器：mpv → ffplay → vlc → xdg-open → nix run nixpkgs#mpv
- 文件在仓库的 `media/` 目录，安装时随配置一起部署到 `/etc/nixos/media/`

**不想下载 mp4（安装更快）**：curl 时加 `--no-apple` 参数

```
curl -L https://raw.githubusercontent.com/Reimilia617/UTNixOS_Pro/main/install.sh | bash -s -- --no-apple
```

用 `--no-apple` 安装的系统没有 badapple.mp4，彩蛋会提示而不是报错；
想补上就把 mp4 放进 `/etc/nixos/media/` 再 `ut` 重建。

---

# Web 管理面板（默认启用）

UTNixOS_Pro 自带一个 **Web 管理面板**：浏览器里完成原本 `ut` 终端菜单能做的所有事。
**新装系统默认开启**，`systemd` 会自动启动面板，浏览器打开：

```
http://127.0.0.1:8090
```

用**系统用户名和密码**登录（PAM 认证，与终端登录一致；只允许 `wheel` 组用户，可在模块里改 `allowedGroup`）。

> 如果之前装的旧系统没有面板，用 `ut menu` 勾选系统模块里的 webui（或手动取消
> `configuration.nix` 中 `./modules/system/webui.nix` 的注释）后重建即可。

## 功能一览

| 功能 | 说明 |
| --- | --- |
| 重建系统 | `nixos-rebuild switch`，实时输出控制台 |
| 更新系统 | 同步 GitHub 代码 + 重建（等同 `ut update`） / 仅更新 Flake + 重建 |
| 模块启停 | 读写 `configuration.nix`（与 `ut menu` 同一套选择逻辑，共用 `.utnixos-pro-selection`） |
| 软件包 | 搜索 nixpkgs、**声明式安装**（写入 `host/packages.nix`，重建后保留）、**临时安装**（`nix profile`，重建后失效） |
| 时间点回滚 | 列出系统 generations（带时间），选择回滚 |
| 系统日志 | `journalctl` 查看 + 实时跟踪（按服务过滤） |
| 清理垃圾 | `nix-collect-garbage -d` |
| 审计 | 所有操作记录在 `/var/lib/utnixos-pro-webui/audit.log` |

## 安全说明（重要）

- 面板以 root 运行（需要执行 nixos-rebuild），**默认只监听 `127.0.0.1`，防火墙零开放**，不会暴露到公网。
- 想在内网其他设备访问时，两种方式：
  - **推荐**：保持 127.0.0.1，用 SSH 隧道 `ssh -L 8090:127.0.0.1:8090 user@主机`
  - 或修改模块选项 `services.utnixos-pro-webui = { address = "0.0.0.0"; allowLan = true; }` 开放防火墙端口（此时密码明文走网络，请仅在可信内网使用，或自备 HTTPS 反代）。
- 登录有频率限制（1 分钟 5 次失败封禁）；所有输入（包名/模块/日志 unit）都有白名单校验，命令以参数数组执行，无 shell 注入面。

## 自定义

```nix
services.utnixos-pro-webui = {
  enable = true;
  port = 8090;                # 端口
  address = "127.0.0.1";      # 监听地址（默认仅本机）
  allowLan = false;           # 允许内网访问（开防火墙端口）
  allowedGroup = "wheel";     # 允许登录的管理员组
};
```

源码在 `webui/` 目录（Go + 原生 JS，零第三方依赖），可单独构建：`nix build .#webui`。
`ut update` / Web 面板的「更新配置」会自动保留 `host/packages.nix`、`host/grub-device.nix` 和 `hardware-configuration.nix`。

---

# 脚本结构（跟 NixOS 配置一样是模块化的）

bash 脚本与 NixOS 配置的 `modules/` 同理，拆成了小模块，方便维护和扩展：

```
install.sh                      # 薄引导器：找到/拉取模块并加载（兼容 curl|bash）
script/
├── main.sh                     # 主程序：加载所有模块 + 命令路由
├── lib/                        # 基础设施（自动加载）
│   ├── env.sh                  # 配置变量（仓库地址、路径、镜像源）
│   ├── util.sh                 # 输出/菜单/sed工具/ASCII画
│   ├── selection.sh            # 模块选择逻辑（改 configuration.nix / home-manager.nix）
│   └── easteregg.sh            # 彩蛋（touhou → Bad Apple）
└── commands/                   # 命令（新增命令=往这里丢一个 .sh 定义 cmd_xxx 即可）
    ├── install.sh              # cmd_install   全新安装
    ├── update.sh               # cmd_update    更新配置
    ├── menu.sh                 # cmd_menu      更换模块
    ├── rollback.sh             # cmd_rollback  系统回滚
    └── dashboard.sh            # cmd_dashboard 管理面板
```

---

# 🙏 致谢与代码来源

> **诚实声明**：这个项目站在了无数开源项目与各位前辈的肩膀上。下面「用了谁的东西、用在了哪里」写得很清楚，这是我对每一位贡献者的敬意，也是我要求自己必须做到的事。

## 直接使用的开源项目

| 项目 | 用途 |
| --- | --- |
| [NixOS](https://nixos.org/) / [nixpkgs](https://github.com/NixOS/nixpkgs) | 系统本体与软件包来源，整个配置的基石 |
| [Home-Manager](https://github.com/nix-community/home-manager) | 声明式管理用户目录（ZSH/git/ssh/fzf/XDG 目录规范） |
| [Oh My ZSH](https://github.com/ohmyzsh/ohmyzsh) | ZSH 插件框架 |
| [Powerlevel10K](https://github.com/romkatv/powerlevel10k) | 终端主题（`romkatv`） |
| [hyfetch](https://github.com/hykilpikonna/hyfetch) | 开机 fetch 彩蛋（`hykilpikonna`） |
| [sops-nix](https://github.com/Mic92/sops-nix) | 密钥管理模板模块（`Mic92`） |
| [disko](https://github.com/nix-community/disko) | 声明式分区模板模块 |
| [impermanence](https://github.com/nix-community/impermanence) | 根分区不持久化模板模块 |
| [nixos-hardware](https://github.com/NixOS/nixos-hardware) | 笔记本硬件优化 |
| [restic](https://github.com/restic/restic) | 定时备份模板模块 |
| [fail2ban](https://github.com/fail2ban/fail2ban) | 安全模板模块 |
| [treefmt / nixfmt](https://github.com/numtide/treefmt) | 代码格式化（`nix fmt`） |
| [statix](https://github.com/nerdypepper/statix) / [deadnix](https://github.com/astro/deadnix) | Nix 静态检查 |

## 东方 GRUB 主题（`themes/grub/th-rm`）

- 主题里的字体与素材：
  - **Maoken 故障宋**（`maoken.pf2`）：猫啃网 / Maoken 免费商用字体
  - **文泉驿正黑**（`wqy.pf2`）：文泉驿开源字体
  - **DejaVu**（`dejavu.pf2`）：开源字体
  - 背景与角色素材为东方 Project 二次创作，版权归原作者，仅供个人学习使用
- 主题的整体设计参考了社区流行的东方 GRUB 主题风格。

## 其它

- 壁纸素材为东方 Project 二次创作（`themes/wallpapers/youmu.png`），版权归原作者所有，仅供个人使用。
- `media/badapple.mp4` 为東方 Project 二次创作影绘视频，版权归原作者。

---

# 👥 贡献者

> 按「贡献的源头」排序：**致敬所有站在前面的开源开发者 → DeepSeek → Reimilia617（本人）**。
> 我一直认为，这个项目 90% 的功劳属于前人，只有剩下的一点点属于我自己。

| 贡献 | 角色 | 说明 |
| --- | --- | --- |
| **所有上游开源开发者** | 奠基者 🏆 | NixOS 生态、Home-Manager、Oh My ZSH、P10K、hyfetch、sops-nix、disko、impermanence、nixos-hardware、各字体/壁纸作者……没有他们的成果就没有这个项目。**功劳最大的是他们。** |
| **DeepSeek** | AI 协作开发者 🤖 | 交互式安装/更新脚本（install.sh）、`ut` 管理中枢、脚本模块化重构、回滚保险方案、CI/测试、进阶模块模板、绝大部分文档撰写。 |
| **Reimilia617** | 项目发起人 / 制作人 👤 | 需求定义与方向、NixOS 配置的架构与模块规划、东方主题/彩蛋的品味把控、素材收集与最终测试。 |

> **为什么这么排？** 一个个人配置仓库，技术上真正难的是「有人先把 NixOS 生态做出来」。所以我把最多的敬意留给上游开源开发者；DeepSeek 帮我把「想做的东西」高效地变成了「能用的代码」；而我负责的是让这一切「符合我的口味」。请把掌声先给前面的人。

---

# 更新日志

## Ver2.6（三个重要 Bug 修复）

- 1. **BIOS 启动无法安装引导加载程序**：引导选择改为「先选引导加载器」——
  GRUB 分为 **UEFI** 与 **BIOS** 两种，另有 systemd-boot；选了 GRUB 之后再问要不要主题。
  - 新增 `modules/boot/grub-bios.nix`（BIOS/MBR 版 GRUB）
  - BIOS 引导会询问目标磁盘（如 `/dev/sda`），写入机器本地文件 `host/grub-device.nix`
    （`ut update` 自动保留），不再需要手动改 `grub.nix` 里的 `"nodev"`
- 2. **进入系统后 `ut` 打不开管理面板**：live 环境判定逻辑错误——
  已装 NixOS 的 PATH 里同样有 `nixos-install`（nixos-install-tools 是系统默认包），
  导致 `ut` 被误判为 live 环境而进入安装界面。现改为：`/etc/nixos` 存在即已装系统，
  live ISO 的判据是无 `/etc/nixos` 且存在默认用户 `nixos`。
- 3. **Web 管理面板无法使用**：
  - 修复 `webui/default.nix`：main 包在 `cmd/webui`，但 buildGoModule 默认只构建模块根目录，
    导致 `nix build .#webui` 构建失败、开启 webui 后整个 `nixos-rebuild` 失败。
    显式声明 `subPackages = [ "./cmd/webui" ]`，产物 `bin/webui` 与 systemd 服务路径对齐。
  - Web 面板改为**默认启用**（系统模块默认勾选 + configuration.nix 默认打开），装完即可访问
    `http://127.0.0.1:8090`
  - KVM 启动冒烟测试新增面板服务/健康检查断言，CI 会真实构建并启动面板验证
- 4. Web 面板模块页新增：GRUB 主题开关、GRUB(BIOS) 目标磁盘输入（与 TUI 共用状态文件）
- 5. 新增上海交大镜像源（`sjtu`，`https://mirror.sjtu.edu.cn/nix-channels/store`），
  菜单与 Web 面板均可见，安装/更新脚本的 substituters 同步支持
- 6. 修正 ESP 挂载点误导：教程改为把 ESP 挂到 `/mnt/boot`（NixOS 默认 GRUB/systemd-boot
  的 EFI 目录是 `/boot`，`/boot/efi` 是 Ubuntu 习惯会导致引导装不上）；
  安装脚本新增专门警告：检测到 ESP 挂在 `/boot/efi` 时会提示改挂 `/boot`
- 7. 再次修复 live 环境判定：live ISO 上同样存在 `/etc/nixos`（上一版误判为已装系统），
  现改用 `/nix/var/nix/profiles/system` + `hardware-configuration.nix` 判已装、
  根文件系统 overlay / nixos 用户判 live
- 8. 安装脚本自动透传代理：检测到 `https_proxy/http_proxy/all_proxy` 环境变量时，
  自动给 `nixos-install` 加 `--option proxy`（store 闭包下载也走代理）
- 9. 引导器 fetch 阶段修复「卡死」：git clone/curl 显式透传代理环境变量、
  低速 30 秒自动中止、curl 加连接/总超时、失败时提示先 export 代理或加 `--no-apple`
- 10. 新增 `ut repair` / `curl ... install.sh | sudo bash -s -- repair` 一键修复：
  /etc/nixos 被搞坏（缺 flake.nix/install.sh）时，保留机器配置、拉取最新代码
  重建 /etc/nixos 并重建系统；先全量备份、失败自动回滚
- 11. `ut update` 加固：tarball 分支下载后强制校验完整性（缺 flake.nix 拒绝替换）、
  git 分支 reset 后校验、替换失败自动回滚——杜绝「/etc/nixos 变成残缺目录」
- 12. 修复入口三合一：管理面板菜单新增「7) 一键修复」；`ut` 自动检测到
  /etc/nixos 损坏（缺 flake.nix）时自动进入修复；curl|bash 传参兼容
  `bash -s -- repair` 参数落在 $0/$1 两种 sh 实现
- 13. 修复两个「ut 崩 / 8090 死」的深层根因：
  - shell 别名 `ut = "sudo /etc/nixos/install.sh"`（fish/zsh/bash）会**覆盖**系统的
    `ut` 二进制，install.sh 可执行位丢失时直接执行报 command not found——
    别名统一改为 `sudo bash /etc/nixos/install.sh`
  - 状态文件 v2 迁移：旧状态（webui 默认开启之前）重放时自动补上 webui，
    不再把默认启用的面板注释掉
  - 安装/更新/修复所有部署路径补 `chmod +x install.sh` 可执行位保险
- 14. **修掉 webui 最大的隐藏 Bug**：`services.utnixos-pro-webui.enable` 之前默认
  `false`，且全仓库没有任何地方把它设为 `true`——configuration.nix 取消注释只是
  导入模块，服务永远不会被创建（rebuild 成功但永远 inactive、8090 永远不通）。
  现改为默认 `true`（导入即启用），想关闭可显式设 `enable = false`

## Ver1.1

- 新增了很多很多种桌面环境（除去原来的 GNOME 和 KDE，还新增了 XFCE，LXQT，Hyprland，COSMIC）
- 引导可选择 Systemd-boot 了，但是默认仍然是 GRUB
- 输入法新增一个可选择的 Fcitx5，默认依旧是 IBus（KDE 用户推荐选 Fcitx5 呢）
- 新增多个可选择镜像源，若发现速度奇慢，排除你的网络的问题后，更换镜像源

## Ver1.2

- 1. 添加了 flake，使用 `nixos-install/nixos-rebuild switch --flake github:Reimilia617/UTNixOS_Pro#reimilia` 命令通过 flake 安装/更新
- 提示：如果你想自定义使用别的模块还是请你 git 到本地修改后使用 (*/ω＼*)

## Ver1.3

- 1. 添加了东方 GRUB 主题，修复了 Very 多的 Bug

## Ver1.4

- 1. 添加了 5 个系统优化插件，详情见 configuration.nix
  - 自动更新 (每天凌晨 3:00)
  - 自动清理垃圾 (每天凌晨 3:15)
  - ZRAM 内存压缩
  - Nix Flakes 实验性功能开启
  - 无需密码自动登录 (默认关闭)
- 2. 默认桌面改为 Xfce
- 3. 修复了 OS-Prober 不可用的问题

## Ver2.0_LTS（LTS 版以后随缘更新了）

- 1. 新增了 Home-Manager（真是个史诗级的更新啊）
  - 目前添加了什么模块？
    - ZSH + Oh My ZSH + Powerlevel10K
    - 快捷别名:
      - 1. sys-update (手动更新系统)
      - 2. clean (手动清理垃圾)
      - 3. ff (hyfetch，随时随地，fetch 一下)
      - 4. ll (ls -al)
      - 5. la (ls -la)
    - 开机名言彩蛋
- 2. 修复了 N 个 Bug，新增了 N 个 Bug ┗|｀O′|┛ 嗷~~
- 3. GNOME 桌面添加默认壁纸，是魂魄妖梦诶(≧∇≦)ﾉ
  - 通过手动修改配置文件还能做到默认使用别的壁纸
  - 目前就 GNOME 桌面是能成功修改默认壁纸的，别的都会炸 o(≧口≦)o
- 4. 移除了 Herobrine
- 5. 操操操！原来之前我一直没加上浏览器，我真是个傻逼ヽ（≧□≦）ノ

## Ver2.1

- 1. 修复 P10K 首次登录弹配置向导卡住终端的问题（默认关闭向导，想自定义外观就运行 `p10k configure`）
- 2. 修复南京大学镜像源域名错误（mirrors.nju.cn → mirrors.nju.edu.cn）
- 3. home-manager 弃用的 `programs.zsh.initExtra` 迁移到 `initContent`
- 4. 临时密码改为哈希存储（openssl passwd -6），不再明文提交
- 5. GNOME 壁纸改为跟随 flake 的 store 路径，不再依赖 /etc/nixos 下的文件
- 6. 自动更新跟随所选镜像源，并同时更新 home-manager input
- 7. 编译器工具链(gcc/rustc/cargo/cmake)不再全局安装，推荐按项目用 `nix develop`
- 8. Hyprland 模块补上 SDDM 登录管理器（Wayland greeter）
- 9. 新增 VM 调试模块（见上方说明）

## Ver2.2（项目更名 UTNixOS_Pro）

- 1. fastfetch 换成 hyfetch（自定义配色的 neofetch 系）
- 2. 新增交互式安装/更新脚本 install.sh（ASCII 字符画 + 菜单选模块 + 自动改配置 + 一键安装/同步/换模块）
- 3. 新增代码格式化：treefmt + nixfmt（nix fmt），静态检查 statix/deadnix
- 4. 新增 GitHub Actions CI（flake check + 启动冒烟测试）
- 5. 新增 KVM 启动冒烟测试：`nix flake check` / `nix build .#checks.x86_64-linux.boot`
- 6. 引入进阶模块输入：sops-nix / disko / impermanence / nixos-hardware（默认不启用）
- 7. 新增 overlays 自定义包入口
- 8. flake 重构为多主机结构（hosts 列表）
- 9. Home-Manager 新增：XDG 目录规范 + programs.git/ssh/fzf/bat/htop 声明式配置
- 10. 新增统一字体模块 fonts.nix（Noto + Nerd Font），zh_CN 模块去重
- 11. 防火墙显式声明（networking.firewall）
- 12. 新增模板模块：secrets(sops) / impermanence / backup(restic) / security(fail2ban) / disko-config

## Ver2.3（ut 系统管理中枢）

- 1. 新增 ut 命令：整个系统的管理接口，输入 `ut` 打开管理面板
  - 重建系统 / 清理构建垃圾 / 选择更换模块 / 更新配置 / 更新 Flake / 系统回滚
- 2. install.sh 升级为管理总脚本：
  - 无参数运行 → 管理面板（live 环境仍是安装向导）
  - 新增回滚模式：`install.sh rollback` / `--rollback`（列出 generations 自由选择回滚）
  - 保险方案：curl 安装脚本 + `--rollback` 参数，本地脚本坏了也能回滚
  - 模块菜单新增 Shell 选择（zsh/bash/fish，自动同步改 configuration.nix 和 home-manager.nix）
- 3. 新增 Fish Shell 支持（modules/shell/fish.nix + home/shell/fish.nix，别名与 zsh 一致）
- 4. 别名更新：新增 `ut` 命令别名，sys-update/clean 继续快捷重建和清理

## Ver2.4（脚本模块化）

- 1. bash 脚本重构为模块化结构（与 NixOS 配置的 modules/ 同理）：
  - install.sh 变成薄引导器（curl|bash 时自动从 GitHub 拉取模块）
  - script/lib/：env(配置) / util(输出·菜单·工具) / selection(模块选择)
  - script/commands/：install / update / menu / rollback / dashboard 五个命令各自独立成文件
  - 新增命令 = 往 script/commands/ 丢一个 .sh 文件定义 cmd_xxx 即可，自动加载
- 2. 修复帮助文本里的 curl 地址拼接错误（改用 RAW_URL）

## Ver2.5（彩蛋 + --no-apple + 最终检查）

- 1. 彩蛋：模块选择界面输入 `touhou` 播放 Bad Apple!!（media/badapple.mp4，自动选播放器）
- 2. --no-apple 参数：跳过 badapple.mp4 的下载（稀疏检出）和部署，加快安装
- 3. media/ 目录：badapple.mp4 随配置一起部署到 /etc/nixos/media/
- 4. 最终 bug 检查：全新安装流程 / 从别人硬件配置构建 / 回滚逻辑 全部实测通过
- 5. 支持 UTNIXOS_PRO_GIT_URL / UTNIXOS_PRO_TARBALL_URL / UTNIXOS_PRO_RAW_URL 环境变量换源（fork 友好）

---

## 📄 License

MIT。详情见 [LICENSE](LICENSE)。
