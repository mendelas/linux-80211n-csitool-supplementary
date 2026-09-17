#!/bin/bash
# Machine inventory + role assignment. Sourced by run_experiment.sh / txpower_sweep.sh / etc.
#
# RULE: IP = MACHINE, permanently. The last octet is the number written on the laptop.
#       Roles (TX / RX) are NOT tied to the IP: every laptop carries both rx_setup.sh and
#       tx_setup.sh, so any machine can be TX or RX. Pick the roles below, per experiment.
#
# Inventory (192.168.100.N):
#   11  HP ProBook 6570b   eth0 88:51:fb:c6:50:77   (LORCON built: TX or RX)
#   12  HP ProBook 6570b   eth0 2c:44:fd:67:36:d5   (no LORCON yet: RX only)
#   13  HP ProBook 6570b   eth0 40:a8:f0:03:0c:33   (LORCON built: TX or RX; added 2026-09)
#   14  (new, 2026-09)  set up with node_setup.sh 14
#   15  (new, 2026-09)  set up with node_setup.sh 15
#   16  (new, 2026-09)  set up with node_setup.sh 16
#   10  = control PC (this machine), not a node
NODE_USER=kota
NODE_NET=192.168.100

# ---- roles for THIS experiment (edit here only) ----
TX_NODE=13              # one machine number. Needs injection/random_packets built there.
RX_NODES=(11 12)        # machine numbers, in rx_id order (0,1,2,...). 1..N machines.
# ---------------------------------------------------

ALL_NODES=(11 12 13 14 15 16)   # everything on the LAN, for check_nodes.sh

node() { echo "$NODE_USER@$NODE_NET.$1"; }
TX=$(node "$TX_NODE")
RXS=(); for n in "${RX_NODES[@]}"; do RXS+=("$(node "$n")"); done
