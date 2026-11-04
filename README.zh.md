<h1 align="center">tailscale-bindhosts</h1>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

<p align="center">
  <a href="https://github.com/PEMessage/tailscale-bindhosts"><img alt="GitHub stars" src="https://img.shields.io/github/stars/PEMessage/tailscale-bindhosts?style=flat-square"></a>
  <a href="https://github.com/PEMessage/tailscale-bindhosts/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/PEMessage/tailscale-bindhosts?style=flat-square"></a>
  <a href="https://github.com/PEMessage/tailscale-bindhosts/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/PEMessage/tailscale-bindhosts/total?style=flat-square"></a>
  <img alt="Magisk, KernelSU, APatch" src="https://img.shields.io/badge/Magisk-KernelSU-APatch-blue?style=flat-square&logo=android&logoColor=white">
  <a href="https://github.com/bindhosts/bindhosts"><img alt="Requires bindhosts" src="https://img.shields.io/badge/requires-bindhosts-informational?style=flat-square"></a>
</p>

## 为什么使用这个模块

Magisk-Tailscaled 很好：`tailscaled` 直接运行在本机，不占用 Android 的 VPN 槽位。但受
Android 限制，它没法像桌面 Linux 那样接管系统 DNS，所以 MagicDNS 名字不会自动生效：
`tailscale status` 能看到 `nas.tailxxxx.ts.net`，浏览器、`ssh` 和其他 App 却解析不了。

MagicDNS 的 IP 基本不变，新设备加入 tailnet 也是低频操作，所以直接把节点列表写进 hosts
就够了：

```
100.101.102.104 nas.tailxxxx.ts.net nas
```

本模块通过 bindhosts 写入 hosts，因此可以和 AdAway、AdGuard 等其他 hosts 模块共存。

## 依赖

需要 root，以及 Magisk、KernelSU、APatch 之一。

1. **[bindhosts](https://github.com/bindhosts/bindhosts)（必须）**：负责管理系统 hosts。本模块
   通过它写入记录，所以能和 AdAway、AdGuard 等其他 hosts 模块共存。未安装时本模块会拒绝安装。

2. **一个 Tailscale 模块（任选其一）**：提供 `tailscaled` 和 `tailscale` 命令，负责登录和后台
   运行；本模块只读取它的状态。
   - [anasfanani/Magisk-Tailscaled](https://github.com/anasfanani/Magisk-Tailscaled)
   - [WayneShao/KernelSU-Tailscaled](https://github.com/WayneShao/KernelSU-Tailscaled)
   - [KyuubiRan/Shellscaled](https://github.com/KyuubiRan/Shellscaled)
   - [Iridule/Tailscale-native-magisk](https://github.com/Iridule/Tailscale-native-magisk)

   布局相同的分支通常也能用，例如 `mgksu/tailscaled`、
   `Magisk-Modules-Alt-Repo/Magisk-Tailscaled`。

官方 Tailscale Android App 不需要本模块。

## 安装

1. 装好 bindhosts 和 Tailscale 模块，确认已登录、节点在线。
2. 刷入本模块 zip。
3. 重启。
4. 在模块管理器里点 `tailscale-bindhosts` 的 Action。
5. 卡片显示 `active` 即写入成功。

显示 `error` 时，先确认 Tailscale 已登录、后台服务正在运行，再点一次 Action。

首次运行会自动寻找 `tailscale` 命令和 socket。装了多套 Tailscale 时可能选错，见
[多套 Tailscale](#多套-tailscale)。

Action 就是手动刷新一次。节点新增、改名或换 IP 后，再点一次。

## 如何工作

```
tailscale status --json  →  tailscale-bindhosts  →  bindhosts
```

模块读取节点名和 IP，生成 hosts 行，交给 bindhosts 合并进系统 hosts。模块没有常驻后台进程，
也没有定时任务；`BOOT_APPLY=1` 只会在开机时短暂执行一次等待。

## 进阶用法（命令行）

重启后可以使用 `tailscale-bindhosts` 命令。root shell 中：

```sh
su
tailscale-bindhosts status
```

找不到命令时：

```sh
sh /data/adb/modules/tailscale-bindhosts/tailscale-bindhosts.sh status
```

命令：

```sh
tailscale-bindhosts status          # 查看配置和状态
tailscale-bindhosts detect          # 列出检测到的 tailscale 和 socket
tailscale-bindhosts use <n>         # 选择第 n 个结果
tailscale-bindhosts preview         # 只打印将要写入的 hosts 行
tailscale-bindhosts apply           # 生成并写入
tailscale-bindhosts unapply         # 撤销写入
tailscale-bindhosts test            # 检查配置的 tailscale 命令
tailscale-bindhosts log 100         # 查看最近 100 行日志
tailscale-bindhosts set KEY VALUE   # 修改一项配置
```

### 配置

配置文件：`/data/adb/tailscale-bindhosts/config`。

| 键 | 默认 | 说明 |
|---|---|---|
| `TS_BIN` | 空 | `tailscale` 命令；空时由 `apply` 自动检测 |
| `TS_SOCKET` | 空 | tailscaled socket；空表示默认值 |
| `TS_ARGS` | 空 | 额外参数，按空格拆分 |
| `ADD_SHORT` | `1` | 写入短名，例如 `nas` |
| `ADD_IPV6` | `1` | 写入 IPv6 地址 |
| `ADD_SELF` | `1` | 包含本机 |
| `BOOT_APPLY` | `0` | 开机时生成一次 |

示例：

```sh
tailscale-bindhosts set ADD_IPV6 0
tailscale-bindhosts set ADD_SHORT 0
tailscale-bindhosts set BOOT_APPLY 1
```

### 多套 Tailscale

```sh
tailscale-bindhosts detect
```

输出类似：

```text
[1] anasfanani/Magisk-Tailscaled
    bin:    /data/adb/tailscale/bin/tailscale
    socket: /data/adb/tailscale/run/tailscaled.sock
    source: settings/default
```

选择并应用：

```sh
tailscale-bindhosts use 2
tailscale-bindhosts apply
```

`use` 会同时写入 `TS_BIN` 和 `TS_SOCKET`，保证命令和 socket 来自同一套安装。只有需要手动覆盖
时才单独用 `set`。

### 刷新与撤销

刷新是手动的：点 Action 或执行 `apply`。`BOOT_APPLY=1` 会在开机且 tailscaled 就绪后生成
一次；之后的刷新仍需手动执行。

`unapply` 会删除写入的条目和生成缓存，保留模块、配置和日志。再次 `apply` 可恢复。

## 生成的条目

每个节点至少一行 FQDN，例如 `100.x.y.z nas.tailxxxx.ts.net`。开启 `ADD_SHORT` 后会加短名
（`nas`）和合法的 `HostName` 别名；跨节点冲突的可选别名会被丢弃，因此 FQDN 是唯一保证保留的
名字。`ADD_IPV6` 和 `ADD_SELF` 分别控制 IPv6 和本机。

## 限制

- 只处理“名字 → IP”，不支持 MagicDNS 的 search domain、split DNS 和 `svc:`。
- 向 tailnet 添加新设备后，可能需要手动刷新一次。
- Android DNS 缓存可能需要重启应用。

## 卸载

在模块管理器里卸载。模块会清理自己写入的 hosts 块和 bindhosts 自定义文件。

## 构建

```sh
./build.sh
# dist/tailscale-bindhosts-<version>.zip
```

需要 `bash` 和 `zip`。

## 许可证

本项目使用 GNU General Public License v3.0 授权，详见 [LICENSE](LICENSE)。
