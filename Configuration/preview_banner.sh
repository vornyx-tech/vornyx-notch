#!/bin/bash
#
# Show one of the closed notch's banners with made-up data, in the running app.
#
# Usage:  ./Configuration/preview_banner.sh <banner>
#         ./Configuration/preview_banner.sh all
#
# Banners: focusOn focusOff vpnConnected vpnDisconnected batteryLow
#          batteryFull bluetooth hotspot timer timerEnd lockScreen
#
# The same list is under Settings > Indicators > Try the banners.

set -euo pipefail

ALL=(focusOn focusOff vpnConnected vpnDisconnected batteryLow batteryFull bluetooth hotspot timer timerEnd lockScreen)

post() {
  /usr/bin/swift - "$1" <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("tech.vornyx.notch.preview"), object: CommandLine.arguments[1],
    userInfo: nil, deliverImmediately: true)
SWIFT
}

case "${1:-}" in
  "") echo "usage: $0 <${ALL[*]// /|}|all>" >&2; exit 1 ;;
  all) for banner in "${ALL[@]}"; do echo "$banner"; post "$banner"; sleep 4; done ;;
  *) post "$1" ;;
esac
