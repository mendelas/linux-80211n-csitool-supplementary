#!/bin/bash
# OPTIONAL: set THIS laptop's clock from the other laptop over the LAN, so the TX log and
# the RX log carry the same time base (the two machines are otherwise free-running; without
# internet their clocks can be minutes apart). Needs the LAN cable + ssh as in multi-rx.
# usage: ./clock_sync.sh <user@other-laptop>      e.g. ./clock_sync.sh kota@192.168.100.13
# Run it on ONE side only (the other side is the reference). Accuracy ~ ssh round trip (ms).
set -u
OTHER=${1:?usage: clock_sync.sh <user@other-laptop>}
echo "before : $(date '+%Y-%m-%d %H:%M:%S.%N')  (this)"
T=$(ssh -o ConnectTimeout=5 "$OTHER" 'date +%s.%N') || { echo "!! ssh $OTHER failed"; exit 1; }
sudo date -s "@$T" >/dev/null || exit 1
echo "after  : $(date '+%Y-%m-%d %H:%M:%S.%N')  (this)"
echo "other  : $(ssh "$OTHER" 'date "+%Y-%m-%d %H:%M:%S.%N"')"
