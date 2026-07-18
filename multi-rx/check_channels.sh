#!/bin/bash
# Check which channels are free — run on the CONTROL PC (uses its own WiFi).
# 5GHz rows (FREQ >= 5000) with no / weak APs = free. Set that ch as CH= in run_experiment.sh.
# usage: ./check_channels.sh
nmcli -f CHAN,FREQ,SIGNAL,SSID dev wifi list --rescan yes | sort -n
