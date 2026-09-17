#!/bin/bash
# Control PC: check every node in hosts.sh (reachable / ssh key / sudo / kernel / CSI fw / role scripts).
# usage: ./check_nodes.sh [N ...]     (default: ALL_NODES from hosts.sh)
HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/hosts.sh"
NODES=("$@"); [ ${#NODES[@]} -gt 0 ] || NODES=("${ALL_NODES[@]}")
role() { [ "$1" = "$TX_NODE" ] && { echo TX; return; }; for i in "${!RX_NODES[@]}"; do [ "${RX_NODES[$i]}" = "$1" ] && { echo "rx$i"; return; }; done; echo "-"; }
printf "%-4s %-4s %-5s %-4s %-5s %-8s %-6s %-6s %-6s %s\n" N role ping ssh sudo kernel csifw rx.sh tx.sh inject
for n in "${NODES[@]}"; do
  h=$(node "$n"); r=$(role "$n")
  if ! ping -c1 -W1 "$NODE_NET.$n" >/dev/null 2>&1; then printf "%-4s %-4s %-5s\n" "$n" "$r" DOWN; continue; fi
  out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$h" '
    printf "%s|" "$(sudo -n true 2>/dev/null && echo ok || echo NO)"
    printf "%s|" "$(uname -r)"
    printf "%s|" "$(ls -l /lib/firmware/iwlwifi-5000-2.ucode 2>/dev/null | grep -q sigcomm2010 && echo csi || echo std)"
    printf "%s|" "$([ -x ~/rx_setup.sh ] && echo ok || echo NO)"
    printf "%s|" "$([ -x ~/tx_setup.sh ] && echo ok || echo NO)"
    printf "%s"  "$([ -x ~/linux-80211n-csitool-supplementary/injection/random_packets ] && echo ok || echo NO)"' 2>/dev/null)
  if [ -z "$out" ]; then printf "%-4s %-4s %-5s %-4s   (ssh failed: run  ssh-copy-id %s)\n" "$n" "$r" up NO "$h"; continue; fi
  IFS='|' read -r sudo_ kern fw rx tx inj <<<"$out"
  printf "%-4s %-4s %-5s %-4s %-5s %-8s %-6s %-6s %-6s %s\n" "$n" "$r" up ok "$sudo_" "$kern" "$fw" "$rx" "$tx" "$inj"
done
echo
echo "need: TX node -> tx.sh+inject ok ; RX nodes -> rx.sh ok ; all -> sudo ok, kernel 3.5.7+, csifw csi"
