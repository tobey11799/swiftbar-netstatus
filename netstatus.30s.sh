#!/bin/bash
# <xbar.title>NetStatus</xbar.title>
# <xbar.version>v0.1.0</xbar.version>
# <xbar.author>Tobey</xbar.author>
# <xbar.author.github>tobey11799</xbar.author.github>
# <xbar.desc>Wired link speed and Wi-Fi signal strength (RSSI / noise / SNR) in the macOS menu bar. No dependencies.</xbar.desc>
# <xbar.dependencies>macOS built-in tools only</xbar.dependencies>
# <xbar.abouturl>https://github.com/tobey11799/swiftbar-netstatus</xbar.abouturl>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# Refresh interval comes from the file name: netstatus.30s.sh = every 30 seconds.
# Data sources: route, ifconfig, networksetup, system_profiler (no sudo, no network calls).

set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export LC_ALL=C

# "Click to copy" handler: the menu calls this script again with "copy <value>".
if [ "${1:-}" = "copy" ]; then
  printf '%s' "${2:-}" | pbcopy
  exit 0
fi

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
FIXTURE_DIR="${NETSTATUS_FIXTURE_DIR:-}"   # test hook, see tests/run.sh

C_FAIR="#ff9500"
C_POOR="#ff3b30"
C_GOOD="#34c759"
MONO="font=Menlo size=12"

# ---------- data sources (overridable for tests) ----------
src_ports()    { if [ -n "$FIXTURE_DIR" ]; then cat "$FIXTURE_DIR/hardwareports.txt" 2>/dev/null; else networksetup -listallhardwareports 2>/dev/null; fi; }
src_ifconfig() { if [ -n "$FIXTURE_DIR" ]; then cat "$FIXTURE_DIR/ifconfig_$1.txt" 2>/dev/null; else ifconfig "$1" 2>/dev/null; fi; }
src_route()    { if [ -n "$FIXTURE_DIR" ]; then cat "$FIXTURE_DIR/route.txt" 2>/dev/null; else route -n get default 2>/dev/null; fi; }
src_airport()  { if [ -n "$FIXTURE_DIR" ]; then cat "$FIXTURE_DIR/airport.json" 2>/dev/null; else system_profiler -json SPAirPortDataType 2>/dev/null; fi; }

# ---------- helpers ----------
AIRPORT_JSON=""
jget() {
  [ -n "$AIRPORT_JSON" ] || return 0
  printf '%s' "$AIRPORT_JSON" | plutil -extract "$1" raw -o - - 2>/dev/null
}

RE_SPEED='([0-9]+)(G?)[Bb][Aa][Ss][Ee]'
RE_OPTS='[<]([^>]*)[>]'
RE_SN='(-?[0-9]+) dBm / (-?[0-9]+) dBm'

# "media: autoselect (1000baseT <full-duplex,flow-control>)"
# -> SPEED_MBPS=1000 SPEED_LONG="1 Gbps" SPEED_SHORT="1G" DUPLEX="full-duplex"
parse_media() {
  local line="$1" num g v
  SPEED_MBPS=0; SPEED_LONG=""; SPEED_SHORT=""; DUPLEX=""
  if [[ $line =~ $RE_SPEED ]]; then
    num="${BASH_REMATCH[1]}"; g="${BASH_REMATCH[2]}"
    if [ -n "$g" ]; then SPEED_MBPS=$((num * 1000)); else SPEED_MBPS=$num; fi
    if [ "$SPEED_MBPS" -ge 1000 ]; then
      v="$(awk -v n="$SPEED_MBPS" 'BEGIN{v=n/1000; if (v==int(v)) printf "%d", v; else printf "%.1f", v}')"
      SPEED_LONG="$v Gbps"; SPEED_SHORT="${v}G"
    else
      SPEED_LONG="$SPEED_MBPS Mbps"; SPEED_SHORT="${SPEED_MBPS}M"
    fi
  fi
  if [[ $line =~ $RE_OPTS ]]; then
    DUPLEX="${BASH_REMATCH[1]}"; DUPLEX="${DUPLEX%%,*}"
  fi
}

# RSSI (dBm) -> LEVEL + LEVEL_COLOR
rssi_level() {
  if   [ "$1" -ge -50 ]; then LEVEL="Excellent"; LEVEL_COLOR="$C_GOOD"
  elif [ "$1" -ge -60 ]; then LEVEL="Good";      LEVEL_COLOR="$C_GOOD"
  elif [ "$1" -ge -70 ]; then LEVEL="Fair";      LEVEL_COLOR="$C_FAIR"
  else                        LEVEL="Poor";      LEVEL_COLOR="$C_POOR"
  fi
}

copy_item() { # label value
  echo "$1 | $MONO bash=\"$SELF\" param1=copy param2=\"$2\" terminal=false tooltip=\"Click to copy\""
}

# ---------- collect: ports & route ----------
PORTS="$(src_ports | awk -F': ' '/^Hardware Port:/{n=$2} /^Device:/{print $2 "\t" n}')"
WIFI_DEV="$(printf '%s\n' "$PORTS" | awk -F'\t' '$2=="Wi-Fi" || $2=="AirPort" {print $1; exit}')"

ROUTE="$(src_route)"
DEF_IF="$(awk '/interface:/{print $2; exit}' <<<"$ROUTE")"
DEF_GW="$(awk '/gateway:/{print $2; exit}' <<<"$ROUTE")"
VPN_IF=""
case "$DEF_IF" in utun*|ipsec*|ppp*|tun*|tap*|wg*) VPN_IF="$DEF_IF" ;; esac

# ---------- collect: wired ----------
W_N=0
while IFS=$'\t' read -r dev name; do
  [ -n "$dev" ] || continue
  [ "$dev" != "$WIFI_DEV" ] || continue
  case "$dev" in bridge*|awdl*|llw*) continue ;; esac
  ifc="$(src_ifconfig "$dev")"
  grep -q 'status: active' <<<"$ifc" || continue
  parse_media "$(grep -m1 'media:' <<<"$ifc")"
  W_DEV[W_N]="$dev"; W_NAME[W_N]="$name"
  W_MBPS[W_N]="$SPEED_MBPS"; W_LONG[W_N]="$SPEED_LONG"; W_SHORT[W_N]="$SPEED_SHORT"; W_DUPLEX[W_N]="$DUPLEX"
  W_IP[W_N]="$(awk '/inet /{print $2; exit}' <<<"$ifc")"
  W_MAC[W_N]="$(awk '/ether /{print $2; exit}' <<<"$ifc")"
  W_N=$((W_N + 1))
done <<<"$PORTS"

# ---------- collect: Wi-Fi ----------
WIFI_STATE="absent"   # absent | off | disconnected | connected
SSID=""; RSSI=0; NOISE=0; CHANNEL=""; PHY=""; TXRATE=""; SECURITY=""; WIFI_IP=""
if [ -n "$WIFI_DEV" ]; then
  AIRPORT_JSON="$(src_airport)"
  base=""
  for i in 0 1 2 3; do
    n="$(jget "SPAirPortDataType.0.spairport_airport_interfaces.$i._name")"
    [ -n "$n" ] || break
    if [ "$n" = "$WIFI_DEV" ]; then base="SPAirPortDataType.0.spairport_airport_interfaces.$i"; break; fi
  done
  if [ -n "$base" ]; then
    cur="$base.spairport_current_network_information"
    sn="$(jget "$cur.spairport_signal_noise")"
    if [[ $sn =~ $RE_SN ]]; then
      WIFI_STATE="connected"
      RSSI="${BASH_REMATCH[1]}"; NOISE="${BASH_REMATCH[2]}"
      SSID="$(jget "$cur._name")"
      CHANNEL="$(jget "$cur.spairport_network_channel")"
      PHY="$(jget "$cur.spairport_network_phymode")"
      TXRATE="$(jget "$cur.spairport_network_rate")"
      SECURITY="$(jget "$cur.spairport_security_mode")"
      SECURITY="${SECURITY#spairport_security_mode_}"; SECURITY="${SECURITY//_/ }"
      WIFI_IP="$(src_ifconfig "$WIFI_DEV" | awk '/inet /{print $2; exit}')"
    elif [ "$(jget "$base.spairport_status_information")" = "spairport_status_off" ]; then
      WIFI_STATE="off"
    else
      WIFI_STATE="disconnected"
    fi
  fi
fi

# ---------- menu bar title ----------
# Prefer the interface carrying the default route; behind a VPN, show the physical link.
PICK=""
i=0
while [ "$i" -lt "$W_N" ]; do
  if [ "${W_DEV[i]}" = "$DEF_IF" ]; then PICK="w:$i"; fi
  i=$((i + 1))
done
if [ -z "$PICK" ]; then
  if [ -n "$DEF_IF" ] && [ "$DEF_IF" = "$WIFI_DEV" ] && [ "$WIFI_STATE" = "connected" ]; then PICK="wifi"
  elif [ "$W_N" -gt 0 ]; then PICK="w:0"
  elif [ "$WIFI_STATE" = "connected" ]; then PICK="wifi"
  else PICK="none"
  fi
fi

# Icon only (the menu bar is narrow). Color carries the state:
# default = fine, orange = wired below 1 Gbps / Wi-Fi Fair, red = Wi-Fi Poor / offline.
case "$PICK" in
  w:*)
    i="${PICK#w:}"; col=""
    if [ "${W_MBPS[i]}" -gt 0 ] && [ "${W_MBPS[i]}" -lt 1000 ]; then col=" sfcolor=$C_FAIR"; fi
    echo " | sfimage=network$col"
    ;;
  wifi)
    rssi_level "$RSSI"; col=""
    if [ "$LEVEL" = "Fair" ] || [ "$LEVEL" = "Poor" ]; then col=" sfcolor=$LEVEL_COLOR"; fi
    echo " | sfimage=wifi$col"
    ;;
  *)
    echo " | sfimage=wifi.slash sfcolor=$C_POOR"
    ;;
esac
echo "---"

# ---------- dropdown: route ----------
if [ -n "$DEF_IF" ]; then
  echo "Default route: $DEF_IF${DEF_GW:+ via $DEF_GW} | $MONO"
else
  echo "No default route | color=$C_POOR"
fi
[ -z "$VPN_IF" ] || echo "VPN active ($VPN_IF), physical link shown below | color=$C_FAIR"
echo "---"

# ---------- dropdown: wired ----------
if [ "$W_N" -eq 0 ]; then
  echo "Ethernet: not connected | sfimage=network"
fi
i=0
while [ "$i" -lt "$W_N" ]; do
  echo "${W_NAME[i]} (${W_DEV[i]}) | sfimage=network"
  dup="${W_DUPLEX[i]}"; col=""
  if { [ "${W_MBPS[i]}" -gt 0 ] && [ "${W_MBPS[i]}" -lt 1000 ]; } || [ "$dup" = "half-duplex" ]; then col=" color=$C_FAIR"; fi
  echo "Link: ${W_LONG[i]:-unknown}${dup:+, $dup} | $MONO$col"
  if [ -n "$col" ]; then echo "Below 1 Gbps or half duplex: check cable, switch port or USB adapter | size=11 color=$C_FAIR"; fi
  [ -z "${W_IP[i]}" ]  || copy_item "IPv4: ${W_IP[i]}" "${W_IP[i]}"
  [ -z "${W_MAC[i]}" ] || copy_item "MAC:  ${W_MAC[i]}" "${W_MAC[i]}"
  i=$((i + 1))
done
echo "---"

# ---------- dropdown: Wi-Fi ----------
case "$WIFI_STATE" in
  absent)       echo "Wi-Fi: no interface | sfimage=wifi.slash" ;;
  off)          echo "Wi-Fi ($WIFI_DEV): off | sfimage=wifi.slash" ;;
  disconnected) echo "Wi-Fi ($WIFI_DEV): not connected | sfimage=wifi.exclamationmark" ;;
  connected)
    if [ -z "$SSID" ] || [ "$SSID" = "<redacted>" ]; then SSID="(SSID hidden by macOS)"; fi
    SSID="${SSID//|/ }"
    rssi_level "$RSSI"
    echo "Wi-Fi ($WIFI_DEV): $SSID | sfimage=wifi"
    echo "Signal: $RSSI dBm ($LEVEL) | $MONO color=$LEVEL_COLOR"
    echo "Noise:  $NOISE dBm, SNR $((RSSI - NOISE)) dB | $MONO"
    [ -z "$CHANNEL" ]  || echo "Channel: $CHANNEL | $MONO"
    [ -z "$PHY" ]      || echo "PHY: $PHY${TXRATE:+, Tx $TXRATE Mbps} | $MONO"
    [ -z "$SECURITY" ] || echo "Security: $SECURITY | $MONO"
    [ -z "$WIFI_IP" ]  || copy_item "IPv4: $WIFI_IP" "$WIFI_IP"
    ;;
esac
echo "---"

# ---------- actions ----------
echo "Run speed test (networkQuality) | bash=/usr/bin/networkQuality terminal=true"
echo "Open Wireless Diagnostics | bash=/usr/bin/open param1=-a param2=\"Wireless Diagnostics\" terminal=false"
echo "Open Network Settings | href=x-apple.systempreferences:com.apple.Network-Settings.extension"
echo "Refresh | refresh=true"
