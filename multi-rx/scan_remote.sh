#!/bin/bash
# Run the channel scan on the RX laptop(s) FROM the control PC over SSH,
# and show the results here (pull model, same as run_experiment.sh).
# The control PC has no Intel 5300, so the injection-band measurement must
# come from an RX; this just drives it remotely and prints the output locally.
# usage: ./scan_remote.sh [user@host ...]     (default: both RX = .11 and .12)
set -u

# ===== settings (match run_experiment.sh) =====
RX0=kota@192.168.100.11
RX1=kota@192.168.100.12
# ==============================================

HOSTS=("$@")
[ ${#HOSTS[@]} -eq 0 ] && HOSTS=("$RX0" "$RX1")

for H in "${HOSTS[@]}"; do
  echo "############################################################"
  echo "# channel scan on RX: $H   ($(date +%H:%M:%S))"
  echo "############################################################"
  ssh "$H" "~/scan_channels.sh" || echo "!! ssh/scan failed on $H"
  echo
done

echo "Pick the emptiest channel (ideally the same at both RX), then set CH="
echo "in run_experiment.sh. Prefer ch48 for MAIN unless it is badly congested."
