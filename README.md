<h1 align="center">tailscale-bindhosts</h1>

<p align="center">English · <a href="README.zh.md">简体中文</a></p>

<p align="center">
  <a href="https://github.com/PEMessage/tailscale-bindhosts"><img alt="GitHub stars" src="https://img.shields.io/github/stars/PEMessage/tailscale-bindhosts?style=flat-square"></a>
  <a href="https://github.com/PEMessage/tailscale-bindhosts/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/PEMessage/tailscale-bindhosts?style=flat-square"></a>
  <a href="https://github.com/PEMessage/tailscale-bindhosts/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/PEMessage/tailscale-bindhosts/total?style=flat-square"></a>
  <img alt="Magisk, KernelSU, APatch" src="https://img.shields.io/badge/Magisk-KernelSU-APatch-blue?style=flat-square&logo=android&logoColor=white">
  <a href="https://github.com/bindhosts/bindhosts"><img alt="Requires bindhosts" src="https://img.shields.io/badge/requires-bindhosts-informational?style=flat-square"></a>
</p>

## Why use this module

Magisk-Tailscaled is a good setup: `tailscaled` runs on the device without occupying Android's
VPN slot. The catch is that Android does not let it take over system DNS, so MagicDNS names do
not resolve. `tailscale status` shows `nas.tailxxxx.ts.net`, but browsers, `ssh`, and other apps
cannot use it.

MagicDNS IPs rarely change, and adding a device to a tailnet is infrequent, so simply injecting
the node list into hosts is enough:

```
100.101.102.104 nas.tailxxxx.ts.net nas
```

This module writes through bindhosts, so it can coexist with AdAway, AdGuard, and other hosts
modules.

## Dependencies

Requirements: root and one of Magisk, KernelSU, or APatch.

1. **[bindhosts](https://github.com/bindhosts/bindhosts) (required)**: manages the system hosts
   file. This module writes through it, so it can coexist with AdAway, AdGuard, and other hosts
   modules. Installation is refused without it.

2. **A Tailscale module (pick one)**: provides `tailscaled` and the `tailscale` command, and
   handles login and background operation. This module only reads its status.
   - [anasfanani/Magisk-Tailscaled](https://github.com/anasfanani/Magisk-Tailscaled)
   - [WayneShao/KernelSU-Tailscaled](https://github.com/WayneShao/KernelSU-Tailscaled)
   - [KyuubiRan/Shellscaled](https://github.com/KyuubiRan/Shellscaled)
   - [Iridule/Tailscale-native-magisk](https://github.com/Iridule/Tailscale-native-magisk)

   Forks with the same layout usually work too, for example `mgksu/tailscaled` and
   `Magisk-Modules-Alt-Repo/Magisk-Tailscaled`.

The official Tailscale Android app does not need this module.

## Install

1. Install bindhosts and a Tailscale module. Make sure Tailscale is logged in and nodes are online.
2. Flash this module's zip.
3. Reboot.
4. Open your module manager and tap the Action button for `tailscale-bindhosts`.
5. The module card shows `active` when the entries were written.

If it shows `error`, check that Tailscale is logged in and its background service is running,
then tap Action again.

On the first run, the module auto-detects the `tailscale` binary and socket. If you have multiple
Tailscale installs and it picks the wrong one, see [Multiple Tailscale installs](#multiple-tailscale-installs).

Action = one manual refresh. After adding, renaming, or re-addressing a node, tap Action again.

## How it works

```
tailscale status --json  →  tailscale-bindhosts  →  bindhosts
```

The module reads node names and IPs, writes hosts lines, and passes them to bindhosts. It has no
persistent background process and no timer; `BOOT_APPLY=1` only starts a short one-shot wait at
boot.

## Advanced usage (CLI)

After reboot, the module creates a `tailscale-bindhosts` command. From a root shell:

```sh
su
tailscale-bindhosts status
```

If the command is not found:

```sh
sh /data/adb/modules/tailscale-bindhosts/tailscale-bindhosts.sh status
```

Commands:

```sh
tailscale-bindhosts status          # show config and state
tailscale-bindhosts detect          # list detected tailscale binaries and sockets
tailscale-bindhosts use <n>         # select the n-th result
tailscale-bindhosts preview         # print the hosts lines without applying
tailscale-bindhosts apply           # generate and apply
tailscale-bindhosts unapply         # remove the applied entries
tailscale-bindhosts test            # check the configured tailscale binary
tailscale-bindhosts log 100         # show the last 100 log lines
tailscale-bindhosts set KEY VALUE   # change one config value
```

### Config

Config lives at `/data/adb/tailscale-bindhosts/config`.

| Key | Default | Description |
|---|---|---|
| `TS_BIN` | empty | `tailscale` binary; auto-detected by `apply` when empty |
| `TS_SOCKET` | empty | tailscaled socket; empty means the default |
| `TS_ARGS` | empty | extra tailscale arguments, split on spaces |
| `ADD_SHORT` | `1` | add short names such as `nas` |
| `ADD_IPV6` | `1` | add IPv6 addresses |
| `ADD_SELF` | `1` | include the local node |
| `BOOT_APPLY` | `0` | generate once at boot |

Examples:

```sh
tailscale-bindhosts set ADD_IPV6 0
tailscale-bindhosts set ADD_SHORT 0
tailscale-bindhosts set BOOT_APPLY 1
```

### Multiple Tailscale installs

```sh
tailscale-bindhosts detect
```

Output looks like this:

```text
[1] anasfanani/Magisk-Tailscaled
    bin:    /data/adb/tailscale/bin/tailscale
    socket: /data/adb/tailscale/run/tailscaled.sock
    source: settings/default
```

Pick one and apply:

```sh
tailscale-bindhosts use 2
tailscale-bindhosts apply
```

`use` writes both `TS_BIN` and `TS_SOCKET` so the binary and socket come from the same install.
Use `set` only for a manual override.

### Refresh and undo

Refresh is manual: tap Action or run `apply`. `BOOT_APPLY=1` generates once at boot after
tailscaled is ready; later refreshes are still manual.

`unapply` removes the entries and generated cache but keeps the module, config, and log. Run
`apply` again to restore.

## Generated entries

Each node gets at least one FQDN line, for example `100.x.y.z nas.tailxxxx.ts.net`. With
`ADD_SHORT` enabled, the first DNS label (`nas`) and a legal `HostName` alias are also added.
Optional aliases that collide across nodes are dropped, so the FQDN is the only guaranteed name.
`ADD_IPV6` and `ADD_SELF` control IPv6 lines and the local node.

## Limitations

- Only name → IP. MagicDNS search domains, split DNS, and `svc:` records are out of scope.
- You may need a manual refresh after adding a new device to the tailnet.
- Android DNS caches may need an app restart.

## Uninstall

Uninstall from your module manager. The module removes its hosts block and the bindhosts custom
file.

## Build

```sh
./build.sh
# dist/tailscale-bindhosts-<version>.zip
```

Requires `bash` and `zip`.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
