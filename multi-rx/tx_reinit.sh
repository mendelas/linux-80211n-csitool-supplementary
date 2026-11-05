#!/bin/bash
# Re-initialise ONLY the TX (driver reload + channel/power/rate + injection restart) while a
# run_experiment.sh capture keeps every RX streaming. Run it from a SECOND terminal during the
# recording. The RX files then hold, in one capture with the scene unchanged, segments separated
# by a TX re-init (visible as a ~10 s gap in the CSI records).
# Purpose (2026-11-05 AoD pilot): does the TX-stream phase conj(H_tx1)*H_txk change on TX re-init
# when nothing else changes? Same change at every RX antenna = per-stream offset (B_t jump);
# different per RX antenna = streams are not one-antenna-each (mixing / TX-side perm).
# usage: RATE=0x1c911 ./tx_reinit.sh        (radio settings must match run_experiment.sh)
# run_experiment.sh's stop_all kills this injection too at the end of the capture.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/hosts.sh"
CH=157; BW=HT40+; PAYLOAD=100; DELAY=1000; IF=wlan1; TXPWR=15
RATE=${RATE:-0x4901}
REMOTE=~/linux-80211n-csitool-supplementary
NPKTS=600000   # 10 min at 1 kHz; stop_all ends it earlier
echo "$(date +%T) TX re-init on $TX (RATE=$RATE)" | tee -a "$HOME/csi_data/$(date +%Y%m%d)/tx_reinit.log"
ssh "$TX" "sudo pkill -f random_packets" 2>/dev/null
# TX setup + injection MUST be one ssh session (LORCON fails across sessions); backgrounded so
# this script returns once the setup lines are printed.
ssh "$TX" "~/tx_setup.sh $CH $BW $RATE $IF $TXPWR; cd $REMOTE/injection && sudo ./random_packets $NPKTS $PAYLOAD 1 $DELAY >/dev/null 2>&1" &
sleep 15
echo "$(date +%T) injection restarted (check that the rxN.bin files are growing again)" | tee -a "$HOME/csi_data/$(date +%Y%m%d)/tx_reinit.log"
