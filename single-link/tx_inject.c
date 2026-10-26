/*
 * tx_inject: single-TX 802.11n injection with a per-second report.
 *
 * injection/random_packets.c with a readable log for the comprehensive test of the
 * 実験試験局 application: the frames are IDENTICAL to random_packets (LORCON on mon0,
 * 802.11 data frame, injection MAC 00:16:ea:12:34:56, LFSR pseudo-random payload from
 * injection/util.c), but instead of a dot per 1000 frames it prints one line per second
 * (frames sent in that second, running total; printed at the END of the second) plus a
 * start / end summary, and it can run for a number of seconds instead of a number of frames.
 *
 * usage: sudo ./tx_inject [-t SECS | -n NPKTS] [-l PAYLOAD_BYTES] [-d DELAY_US] [-m MODE] [-p]
 *   -t SECS   transmit for SECS seconds (default: until Ctrl-C / SIGTERM, or -n)
 *   -n NPKTS  transmit NPKTS frames
 *   -l BYTES  payload length (default 100, as multi-rx/run_experiment.sh)
 *   -d US     inter-frame interval in microseconds (default 1000 = 1000 frames/s)
 *   -m MODE   0 = my MAC as source, 1 = injection MAC (default 1, as every script here)
 *   -p        plain lines without timestamps (the control PC stamps them, see run_test.sh)
 * Radio (channel / bandwidth / txpower / monitor_tx_rate) must be set BEFORE, in the same
 * shell session (tx_test.sh / run_test.sh do this; LORCON fails across ssh sessions).
 * Needs LORCON (lorcon-old) like random_packets: build with `make tx_inject` on the TX node.
 *
 * (c) 2008-2011 Daniel Halperin <dhalperi@cs.washington.edu> for the injection part.
 */
#include <linux/types.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <tx80211.h>
#include <tx80211_packet.h>

#include "util.h"          /* ../injection/util.h: generate_payloads, get_mac_address */

#define DATETIME "%Y-%m-%d %H:%M:%S"

struct lorcon_packet {
	__le16	fc;
	__le16	dur;
	u_char	addr1[6];
	u_char	addr2[6];
	u_char	addr3[6];
	__le16	seq;
	u_char	payload[0];
} __attribute__ ((packed));

static struct tx80211 tx;
static struct tx80211_packet tx_packet;
static uint8_t *payload_buffer;
#define PAYLOAD_SIZE	2000000

static volatile sig_atomic_t stop_flag = 0;
static void on_signal(int sig) { (void)sig; stop_flag = 1; }
static int plain = 0;

static inline void payload_memcpy(uint8_t *dest, uint32_t length, uint32_t offset)
{
	uint32_t i;
	for (i = 0; i < length; ++i)
		dest[i] = payload_buffer[(offset + i) % PAYLOAD_SIZE];
}

static void fmt_time(time_t t, const char *fmt, char *buf, size_t n)
{
	struct tm tm; localtime_r(&t, &tm); strftime(buf, n, fmt, &tm);
}

/* "HH:MM:SS  " prefix, or nothing in plain mode */
static const char *stamp(time_t t, char *buf, size_t n)
{
	if (plain) { buf[0] = 0; return buf; }
	fmt_time(t, "%H:%M:%S  ", buf, n); return buf;
}

static const char *mac_str(const u_char *m, char *buf)
{
	sprintf(buf, "%02x:%02x:%02x:%02x:%02x:%02x", m[0], m[1], m[2], m[3], m[4], m[5]);
	return buf;
}

static void init_lorcon(void)
{
	int drivertype = tx80211_resolvecard("iwlwifi");
	if (tx80211_init(&tx, "mon0", drivertype) < 0) {
		fprintf(stderr, "Error initializing LORCON: %s\n", tx80211_geterrstr(&tx));
		exit(1);
	}
	if (tx80211_open(&tx) < 0) {
		fprintf(stderr, "Error opening LORCON interface (mon0 up? sudo?)\n");
		exit(1);
	}
	tx80211_initpacket(&tx_packet);
}

static void sec_line(time_t t_end, long in_sec, long total, time_t t0)
{
	char st[16]; stamp(t_end, st, sizeof st);
	printf("%ssent %5ld frames/s  total %7ld  (elapsed %ld s)\n", st, in_sec, total, (long)(t_end - t0));
}

int main(int argc, char **argv)
{
	uint32_t num_packets = 0, packet_size = 100, mode = 1, delay_us = 1000;
	int secs = 0, opt;
	while ((opt = getopt(argc, argv, "t:n:l:d:m:ph")) != -1) {
		switch (opt) {
		case 't': secs = atoi(optarg); break;
		case 'n': num_packets = (uint32_t)strtoul(optarg, NULL, 10); break;
		case 'l': packet_size = (uint32_t)strtoul(optarg, NULL, 10); break;
		case 'd': delay_us = (uint32_t)strtoul(optarg, NULL, 10); break;
		case 'm': mode = (uint32_t)strtoul(optarg, NULL, 10); break;
		case 'p': plain = 1; break;
		default:
			fprintf(stderr, "usage: %s [-t SECS | -n NPKTS] [-l PAYLOAD_BYTES] [-d DELAY_US] [-m 0|1] [-p]\n", argv[0]);
			return opt == 'h' ? 0 : 1;
		}
	}
	if (mode > 1) { fprintf(stderr, "mode must be 0 or 1\n"); return 1; }
	if (packet_size == 0 || packet_size > 2300) { fprintf(stderr, "payload must be 1..2300 bytes\n"); return 1; }

	payload_buffer = malloc(PAYLOAD_SIZE);
	if (!payload_buffer) { perror("malloc payload buffer"); return 1; }
	generate_payloads(payload_buffer, PAYLOAD_SIZE);

	init_lorcon();

	struct lorcon_packet *packet = malloc(sizeof(*packet) + packet_size);
	if (!packet) { perror("malloc packet"); return 1; }
	packet->fc = (0x08 /* Data frame */ | (0x0 << 8) /* Not To-DS */);
	packet->dur = 0xffff;
	if (mode == 0) {
		memcpy(packet->addr1, "\x00\x16\xea\x12\x34\x56", 6);
		get_mac_address(packet->addr2, "mon0");
		memcpy(packet->addr3, "\x00\x16\xea\x12\x34\x56", 6);
	} else {
		memcpy(packet->addr1, "\x00\x16\xea\x12\x34\x56", 6);
		memcpy(packet->addr2, "\x00\x16\xea\x12\x34\x56", 6);
		memcpy(packet->addr3, "\xff\xff\xff\xff\xff\xff", 6);
	}
	packet->seq = 0;
	tx_packet.packet = (uint8_t *)packet;
	tx_packet.plen = sizeof(*packet) + packet_size;

	struct sigaction sa, old; memset(&sa, 0, sizeof sa); sa.sa_handler = on_signal;
	sigaction(SIGINT, NULL, &old); if (old.sa_handler != SIG_IGN) sigaction(SIGINT, &sa, NULL);   /* keep an inherited SIG_IGN */
	sigaction(SIGTERM, &sa, NULL);                   /* run_test.sh stops us with pkill -TERM -> clean end summary */
	setvbuf(stdout, NULL, _IOLBF, 0);                /* lines reach `tee` / ssh / the terminal immediately */

	char ts[64], m1[18], m2[18], m3[18];
	printf("Frame    : IEEE 802.11 data frame (%zu-byte header + %u-byte pseudo-random (LFSR) payload + 4-byte FCS = %zu bytes)\n",
	       sizeof(*packet), packet_size, sizeof(*packet) + packet_size + 4);
	printf("DA / SA / BSSID : %s / %s / %s   (one-way injection, no acknowledgement)\n",
	       mac_str(packet->addr1, m1), mac_str(packet->addr2, m2), mac_str(packet->addr3, m3));
	if (delay_us) printf("Interval : %u us (= %.0f frames/s)", delay_us, 1e6 / delay_us); else printf("Interval : none (as fast as possible)");
	if (secs > 0) printf("   duration : %d s\n", secs);
	else if (num_packets) printf("   count : %u frames\n", num_packets);
	else printf("   duration : until stopped\n");

	time_t t0 = time(NULL), cur_sec = t0;
	if (plain) printf("--- TX start ---\n");
	else { fmt_time(t0, DATETIME, ts, sizeof ts); printf("--- TX start %s ---\n", ts); }

	struct timespec start, now;
	clock_gettime(CLOCK_MONOTONIC, &start);
	uint32_t i; long in_sec = 0, total = 0, failed = 0;
	for (i = 0; !stop_flag && (num_packets == 0 || i < num_packets); ++i) {
		payload_memcpy(packet->payload, packet_size, (i * packet_size) % PAYLOAD_SIZE);

		clock_gettime(CLOCK_MONOTONIC, &now);
		long elapsed_us = (now.tv_sec - start.tv_sec) * 1000000L + (now.tv_nsec - start.tv_nsec + 500) / 1000;
		if (secs > 0 && elapsed_us >= (long)secs * 1000000L) break;
		if (delay_us) {
			long diff = (long)delay_us * i - elapsed_us;           /* same pacing as random_packets */
			if (diff > 0 && diff < (long)delay_us) usleep(diff);
			if (stop_flag) break;
		}

		int ret = tx80211_txpacket(&tx, &tx_packet);
		if (ret < 0) {
			if (++failed <= 3) fprintf(stderr, "Unable to transmit packet: %s\n", tx.errstr);
			if (failed >= 100) { fprintf(stderr, "100 failures, giving up\n"); break; }
		} else { in_sec++; total++; }

		time_t t = time(NULL);
		if (t != cur_sec) {                           /* a wall-clock second completed */
			sec_line(t, in_sec, total, t0);
			in_sec = 0; cur_sec = t;
		}
	}
	time_t t1 = time(NULL);
	if (in_sec) sec_line(t1, in_sec, total, t0);      /* the partial last second */

	clock_gettime(CLOCK_MONOTONIC, &now);
	double span = (now.tv_sec - start.tv_sec) + (now.tv_nsec - start.tv_nsec) * 1e-9;
	const char *why = stop_flag ? " (Ctrl-C / SIGTERM)" : "";
	if (plain) printf("--- TX end%s ---\n", why);
	else { fmt_time(t1, DATETIME, ts, sizeof ts); printf("--- TX end %s%s ---\n", ts, why); }
	printf("sent %ld frames / %.1f s = %.0f frames/s   failed %ld\n", total, span, span > 0 ? total / span : 0.0, failed);
	return failed && !total ? 1 : 0;          /* no tx80211_close: random_packets does not call it either */
}
