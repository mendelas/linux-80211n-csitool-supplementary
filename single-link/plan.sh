#!/bin/bash
# Test plan for the comprehensive test (sourced by run_plan.sh; run_test.sh also reads
# NAME_PREFIX / SECS defaults from here). EDIT THIS FILE to change what is tested:
# which devices, in which order, at which centre frequency / bandwidth, for how long.
# Everything here can also be given on the command line (see run_test.sh / run_plan.sh -h).

# Display name = "<NAME_PREFIX>-Dev<N>"  -> appears as the 2nd line of every report block,
# with " (counterpart)" appended on the RX block.
NAME_PREFIX=NICT-ISAC

# Devices under test, in test order. Each entry is "<dev number>" or "<dev number>:<TX machine>"
# where <TX machine> is the laptop number from multi-rx/hosts.sh (192.168.100.<N>) that
# carries that device. Without ":<TX machine>" the TX_NODE of hosts.sh is used, i.e. the
# same laptop every time (swap the device / card between runs by hand).
DEVICES=(1 2 3)
# DEVICES=(1:13 2:14 3:15)        # <- example: Dev1 on laptop 13, Dev2 on 14, Dev3 on 15

# Frequency cases per device, in test order: "<centre MHz> <bandwidth MHz>"
# (5795/40 = ch157 HT40+ (157+161); 5765/20 = ch153; 5785/20 = ch157; 5805/20 = ch161)
CASES=(
  "5795 40"
  "5765 20"
  "5785 20"
  "5805 20"
)

# Recording time per case, in seconds of confirmed reception (TX runs ~2 min longer at most
# while waiting for the 5 GHz CSI start-up; see run_test.sh STARTUP_WAIT).
SECS=60
