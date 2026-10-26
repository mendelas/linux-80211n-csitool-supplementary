# single-link: 1 TX -> 1 RX test tools (no control PC). Build ON the laptop that uses it.
#   RX laptop:  make csi_report   (needs only the connector header, like multi-rx/csi_stream)
#   TX laptop:  make tx_inject    (needs LORCON lorcon-old, like injection/random_packets)
#   make        -> csi_report, plus tx_inject when LORCON is installed
CC = gcc
CFLAGS = -O2 -Wall

HAVE_LORCON := $(shell ldconfig -p 2>/dev/null | grep -q liborcon && echo yes)

all: csi_report $(if $(HAVE_LORCON),tx_inject,)

csi_report: csi_report.c ../netlink/iwl_connector.h ../netlink/bfee.h ../netlink/connector_users.h
	$(CC) $(CFLAGS) -o $@ $< -lm

# connector_users.h carries CN_NETLINK_USERS of the RUNNING kernel (3.5.7 -> 10, newer -> 11);
# the netlink Makefile generates it from the kernel build headers. Never hard-code it.
../netlink/connector_users.h:
	$(MAKE) -C ../netlink connector_users.h

tx_inject: tx_inject.c ../injection/util.c ../injection/util.h
	$(CC) $(CFLAGS) -Wno-unknown-pragmas -I../injection -o $@ tx_inject.c ../injection/util.c -lorcon -lm -lrt

clean:
	rm -f csi_report tx_inject

.PHONY: all clean
