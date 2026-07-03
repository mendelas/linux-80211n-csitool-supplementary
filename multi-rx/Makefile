# Control-PC tools (build here): csi_recv, csi_merge, read_merged
# RX tool (build on each RX laptop): csi_stream  (needs the netlink headers)
all: csi_recv csi_merge read_merged
csi_recv: csi_recv.cpp ; g++ -O2 -o $@ $<
csi_merge: csi_merge.cpp ; g++ -O2 -o $@ $<
read_merged: read_merged.cpp ; g++ -O2 -o $@ $<
csi_stream: csi_stream.c ; gcc -O2 -o $@ $<
clean: ; rm -f csi_recv csi_merge read_merged csi_stream
