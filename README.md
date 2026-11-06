# swiftbar-netstatus

A tiny [SwiftBar](https://github.com/swiftbar/SwiftBar) / [xbar](https://github.com/matryer/xbar) plugin that shows your **wired link speed** and **Wi-Fi signal strength** in the macOS menu bar.

- Zero dependencies: one bash script using macOS built-ins (`route`, `ifconfig`, `networksetup`, `system_profiler`, `plutil`)
- No `sudo`, no network requests, no background daemon
- Works behind a VPN: shows the physical link under the tunnel

## What it shows

Menu bar: **icon only**, to keep the menu bar narrow. The color carries the state:

| State | Icon |
|---|---|
| Ethernet, 1 Gbps or faster | network icon |
| Ethernet below 1 Gbps (bad cable / port / USB 2.0 adapter) | network icon, orange |
| Wi-Fi, Excellent / Good | Wi-Fi icon |
| Wi-Fi, Fair / Poor | Wi-Fi icon, orange / red |
| No connection | crossed-out Wi-Fi icon, red |

Speed, signal, VPN and everything else are in the dropdown.

Dropdown:

- Default route interface and gateway, VPN indicator
- Each active Ethernet port: negotiated speed, duplex, IPv4, MAC (click to copy)
- Wi-Fi: SSID, RSSI with level, noise and SNR, channel / band / width, PHY mode, Tx rate, security, IPv4
- Actions: run `networkQuality` speed test, open Wireless Diagnostics, open Network Settings, refresh

Wi-Fi signal levels (RSSI): Excellent ≥ -50, Good ≥ -60, Fair ≥ -70, Poor < -70 dBm.

## Install

```bash
brew install --cask swiftbar
# pick a plugin folder when SwiftBar first starts, then:
cp netstatus.30s.sh "<your SwiftBar plugin folder>/"
chmod +x "<your SwiftBar plugin folder>/netstatus.30s.sh"
```

The refresh interval comes from the file name. Rename to `netstatus.10s.sh` or `netstatus.1m.sh` to change it.

## Notes

- On recent macOS versions the Wi-Fi SSID can be redacted by the system. It then shows as "(SSID hidden by macOS)". Signal values are not affected.
- The negotiated Ethernet speed is the link between your Mac and the switch or router. It is not your Internet bandwidth. Use the speed test action for that.

## Development

```bash
./tests/run.sh            # check the title for each fixture
VERBOSE=1 ./tests/run.sh  # also print the full menu output
```

Fixtures live in `tests/fixtures/<case>/`. Each one holds captured outputs of `networksetup -listallhardwareports`, `route -n get default`, `ifconfig <dev>` and `system_profiler -json SPAirPortDataType`. The plugin reads them when `NETSTATUS_FIXTURE_DIR` is set.

---

## 中文说明

在 macOS 菜单栏显示**有线协商速率**和 **Wi-Fi 信号强度**的 SwiftBar 插件。只用系统自带命令，不需要 sudo，也不发网络请求；开着 VPN 时显示隧道下面的物理链路。

安装：`brew install --cask swiftbar`，再把 `netstatus.30s.sh` 复制到 SwiftBar 的插件目录并 `chmod +x`。文件名里的 `30s` 就是刷新间隔。

## License

MIT
