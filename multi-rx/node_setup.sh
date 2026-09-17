#!/bin/bash
# One-shot setup of a NEW laptop as a multi-rx node. Run ON that laptop, locally, once.
# usage: ./node_setup.sh <N> [wired_if]
#   N        = machine number -> this laptop becomes 192.168.100.N  (WRITE N ON THE LAPTOP)
#   wired_if = wired interface (auto-detected: eth0 / en*)
# Does (idempotent): static IP outside NetworkManager, sshd, NOPASSWD sudo,
#   ~/rx_setup.sh + ~/tx_setup.sh (so the node can take EITHER role), csi_stream build,
#   random_packets build if LORCON is installed.
# Does NOT do (see README 3-2, needs a reboot): GRUB default -> 3.5.7, CSI firmware symlink.
# apt steps need internet -> run this while the laptop still has WiFi (standard firmware).
set -u
N=${1:?usage: node_setup.sh <N> [wired_if]   (N = 11..254)}
[ "$N" -ge 11 ] && [ "$N" -le 254 ] || { echo "N must be 11..254 (10 = control PC)"; exit 1; }
IF=${2:-$(ls /sys/class/net | grep -E '^(eth|en)' | head -1)}
[ -n "$IF" ] || { echo "no wired interface found; pass it as 2nd arg"; exit 1; }
IP=192.168.100.$N
SUPP=$HOME/linux-80211n-csitool-supplementary
[ -d "$SUPP/multi-rx" ] || { echo "clone linux-80211n-csitool-supplementary into ~ first"; exit 1; }

echo "=== [1/5] static IP $IP on $IF (/etc/network/interfaces, NM-independent) ==="
if grep -qE "^\s*address 192\.168\.100\." /etc/network/interfaces; then
  echo "  already has a 192.168.100.x entry:"; grep -nE 'iface|address' /etc/network/interfaces | sed 's/^/    /'
  grep -q "address $IP\$" /etc/network/interfaces || echo "  !! and it is NOT $IP -> fix /etc/network/interfaces by hand"
else
  sudo tee -a /etc/network/interfaces >/dev/null <<EOT

auto $IF
iface $IF inet static
    address $IP
    netmask 255.255.255.0
EOT
fi
sudo ifdown "$IF" 2>/dev/null; sudo ifup "$IF" 2>/dev/null
ip addr show "$IF" | grep -o 'inet [0-9.]*' || echo "  !! no IPv4 on $IF"

echo "=== [2/5] sshd + NOPASSWD sudo ==="
dpkg -s openssh-server >/dev/null 2>&1 || sudo apt-get install -y openssh-server
sudo service ssh start 2>/dev/null
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/csi >/dev/null && sudo chmod 440 /etc/sudoers.d/csi
sudo -n true 2>/dev/null && echo "  sudo NOPASSWD ok" || echo "  !! sudo still asks a password"

echo "=== [3/5] role scripts (both, so this node can be TX or RX) ==="
cp "$SUPP/multi-rx/rx_setup.sh" "$SUPP/multi-rx/tx_setup.sh" ~/ && chmod +x ~/rx_setup.sh ~/tx_setup.sh && ls -l ~/rx_setup.sh ~/tx_setup.sh

echo "=== [4/5] build csi_stream (RX) and random_packets (TX) ==="
make -C "$SUPP/multi-rx" csi_stream || echo "  !! csi_stream build failed (netlink headers / gcc?)"
if [ -x "$SUPP/injection/random_packets" ]; then echo "  random_packets present"
elif ldconfig -p | grep -q liborcon; then make -C "$SUPP/injection" || echo "  !! random_packets build failed"
else echo "  !! LORCON not installed -> RX-only node. For TX: lorcon-old (README 3-3) then make -C injection"
fi

echo "=== [5/5] status ==="
echo "  hostname : $(hostname)"
echo "  IP       : $(ip -o -4 addr show "$IF" | awk '{print $4}')   ($IF $(cat /sys/class/net/$IF/address))"
echo "  wifi IFs : $(ls /sys/class/net | grep -E '^wl' | tr '\n' ' ')   <- scripts expect wlan1; if not, change IF= in run_experiment.sh / rx_setup.sh / tx_setup.sh"
echo "  kernel   : $(uname -r)   <- must be 3.5.7+ at experiment time (GRUB default, README 3-2)"
echo "  firmware : $(ls -l /lib/firmware/iwlwifi-5000-2.ucode 2>/dev/null | grep -o 'sigcomm2010' || echo 'standard (switch to CSI fw before experiment, README 3-2)')"
echo "  TX able  : $([ -x "$SUPP/injection/random_packets" ] && echo yes || echo no)"
echo
echo "Now add '$N' to ALL_NODES in multi-rx/hosts.sh on the control PC and run ./check_nodes.sh there."
