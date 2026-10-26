/*
 * csi_report: single-RX CSI capture with a human-readable per-second report.
 *
 * For the comprehensive-test log of the 実験試験局 application (1 TX -> 1 RX). Reads the
 * CSI tool records either from the netlink connector (on the RX laptop, exactly like
 * netlink/log_to_file.c) or from a .csi byte stream on stdin (on the control PC, fed by
 * multi-rx/csi_stream over ssh), saves every record in the standard CSI-tool .csi framing
 * ([uint16 BE len][payload], readable by matlab/read_bf_file.m) and prints ONE line per
 * second instead of one per record (a 1000 Hz PRF would be unreadable): CSI records in
 * that second, running total, estimated loss (bfee_count gaps), total RSS in dBm (same
 * formula as matlab/get_total_rss.m), raw RSSI a/b/c, AGC, Ntx x Nrx and the decoded rate
 * field (HT20/HT40, MCS). Each line is printed at the END of the second it summarizes.
 *
 * usage: sudo ./csi_report [-t SECS] [-i] [-p] [out.csi]
 *   -t SECS   stop SECS seconds after the FIRST CSI record (default: run until Ctrl-C / EOF)
 *   -i        read a .csi stream from stdin instead of netlink (control PC / replay, no sudo)
 *   -p        plain lines without timestamps (the caller stamps them, see run_test.sh)
 *   out.csi   raw record file (omit = report only)
 * Ctrl-C (SIGINT), SIGTERM or end of the stdin stream ends the capture cleanly and prints
 * the summary.
 *
 * Record payload: payload[0] = connector code (0xbb = CSI/BFEE), payload[1..] =
 * struct iwl_bfee_notif (netlink/bfee.h): timestamp_low, bfee_count, Nrx, Ntx,
 * rssiA/B/C, noise, agc, antenna_sel, len, fake_rate_n_flags, CSI matrix.
 */
#include "../netlink/iwl_connector.h"
#include "../netlink/bfee.h"

#include <errno.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <linux/netlink.h>

#define MAX_REC 4096
#define CODE_BFEE 0xbb          /* IWL_CONN_BFEE_NOTIF (netlink/iwl_structs.h): a CSI record */
#define IDLE_LINE_EVERY 10      /* seconds between "waiting" lines while nothing arrives */
#define DATETIME "%Y-%m-%d %H:%M:%S"

static volatile sig_atomic_t stop_flag = 0;
static void on_signal(int sig) { (void)sig; stop_flag = 1; }
static int plain = 0;           /* -p: no timestamps */

/* ---- per-second accumulator ---- */
struct sec {
	long n;                 /* CSI records in this second */
	double sa, sb, sc;      /* sum of raw RSSI a/b/c */
	double srss; long nrss; /* sum of total RSS [dBm] over records that had any RSSI */
	double sagc;
	int ntx, nrx, mixed_shape;
	uint16_t rate; int mixed_rate;
	long lost;
};
static void sec_reset(struct sec *s) { memset(s, 0, sizeof *s); s->ntx = s->nrx = -1; s->rate = 0xffff; }

/* total RSS in dBm, as matlab/get_total_rss.m: db(sum of dbinv(rssi_x != 0)) - 44 - agc */
static int total_rss_dbm(const struct iwl_bfee_notif *b, double *out)
{
	double mag = 0;
	if (b->rssiA) mag += pow(10.0, (uint8_t)b->rssiA / 10.0);
	if (b->rssiB) mag += pow(10.0, (uint8_t)b->rssiB / 10.0);
	if (b->rssiC) mag += pow(10.0, (uint8_t)b->rssiC / 10.0);
	if (mag <= 0) return 0;
	*out = 10.0 * log10(mag) - 44.0 - b->agc;
	return 1;
}

/* iwlagn rate_n_flags (netlink/iwl_structs.h): bit8 HT, bit11 40MHz, bits4:0 MCS index */
static const char *rate_str(uint16_t r, char *buf, size_t n)
{
	if (r == 0xffff) snprintf(buf, n, "-");
	else if (r & 0x100) snprintf(buf, n, "HT%s MCS%u", (r & 0x800) ? "40" : "20", r & 0x1f);
	else snprintf(buf, n, "legacy 0x%04x", r);
	return buf;
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

static void print_sec(time_t t_end, const struct sec *s, long total)
{
	char st[16], rs[32]; stamp(t_end, st, sizeof st);
	if (s->n == 0) { printf("%srecv     0 rec/s  total %7ld\n", st, total); return; }
	printf("%srecv %5ld rec/s  total %7ld  lost %ld  RSS %6.1f dBm (rssi %.0f/%.0f/%.0f agc %.0f)  Ntx x Nrx %dx%d%s  %s%s\n",
	       st, s->n, total, s->lost,
	       s->nrss ? s->srss / s->nrss : NAN,
	       s->sa / s->n, s->sb / s->n, s->sc / s->n, s->sagc / s->n,
	       s->ntx, s->nrx, s->mixed_shape ? "(mixed)" : "",
	       rate_str(s->rate, rs, sizeof rs), s->mixed_rate ? "(mixed)" : "");
}

/* ---- input: netlink connector (as log_to_file.c) or a .csi stream on stdin ---- */
static int open_netlink(void)
{
	struct sockaddr_nl proc_addr;
	int fd = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_CONNECTOR);
	if (fd == -1) { perror("socket (sudo?)"); return -1; }
	memset(&proc_addr, 0, sizeof proc_addr);
	proc_addr.nl_family = AF_NETLINK;
	proc_addr.nl_pid = getpid();
	proc_addr.nl_groups = CN_IDX_IWLAGN;
	if (bind(fd, (struct sockaddr *)&proc_addr, sizeof proc_addr) == -1) { perror("bind"); close(fd); return -1; }
	int on = proc_addr.nl_groups;
	if (setsockopt(fd, 270 /* SOL_NETLINK */, NETLINK_ADD_MEMBERSHIP, &on, sizeof on)) { perror("setsockopt"); close(fd); return -1; }
	return fd;
}

static int read_full(int fd, void *buf, size_t n)
{
	uint8_t *p = buf; size_t got = 0;
	while (got < n) {
		ssize_t r = read(fd, p + got, n - got);
		if (r < 0 && errno == EINTR) { if (stop_flag) return 0; continue; }
		if (r <= 0) return 0;
		got += (size_t)r;
	}
	return 1;
}

/* returns record length > 0; 0 = end of input / stop; -1 = nothing usable this time */
static int next_record(int fd, int from_stdin, uint8_t *rec, char *nlbuf, size_t nlbuf_sz)
{
	if (from_stdin) {
		uint16_t l_be; if (!read_full(fd, &l_be, 2)) return 0;
		uint16_t l = ntohs(l_be);
		if (l == 0 || l > MAX_REC) { fprintf(stderr, "csi_report: bad record length %u\n", l); return 0; }
		if (!read_full(fd, rec, l)) return 0;
		return l;
	}
	ssize_t got = recv(fd, nlbuf, nlbuf_sz, 0);
	if (got < 0) { if (errno == EINTR || errno == EAGAIN) return -1; perror("recv"); return 0; }
	if ((size_t)got < NLMSG_HDRLEN + sizeof(struct cn_msg)) return -1;
	struct cn_msg *cmsg = NLMSG_DATA(nlbuf);
	size_t l = cmsg->len;
	if (l == 0 || l > MAX_REC || NLMSG_HDRLEN + sizeof(struct cn_msg) + l > (size_t)got) return -1;
	memcpy(rec, cmsg->data, l);
	return (int)l;
}

int main(int argc, char **argv)
{
	int secs = 0, from_stdin = 0, opt;
	while ((opt = getopt(argc, argv, "t:iph")) != -1) {
		if (opt == 't') secs = atoi(optarg);
		else if (opt == 'i') from_stdin = 1;
		else if (opt == 'p') plain = 1;
		else { fprintf(stderr, "usage: %s [-t SECS] [-i] [-p] [out.csi]\n", argv[0]); return opt == 'h' ? 0 : 1; }
	}
	const char *outpath = (optind < argc) ? argv[optind] : NULL;
	FILE *out = NULL;
	if (outpath) { out = fopen(outpath, "wb"); if (!out) { perror(outpath); return 1; } }

	int fd = from_stdin ? 0 : open_netlink();
	if (fd < 0) return 1;

	/* no SA_RESTART: poll/recv return EINTR. SIGINT stays ignored if the caller ignored it
	 * (bash does that for background pipelines: run_test.sh wants EOF, not Ctrl-C, to end us) */
	struct sigaction sa, old; memset(&sa, 0, sizeof sa); sa.sa_handler = on_signal;
	sigaction(SIGINT, NULL, &old); if (old.sa_handler != SIG_IGN) sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	setvbuf(stdout, NULL, _IOLBF, 0);                /* lines reach `tee` / ssh / the terminal immediately */

	static uint8_t rec[MAX_REC]; static char nlbuf[8192];
	struct sec cur; sec_reset(&cur);
	time_t cur_sec = time(NULL), first_t = 0, last_t = 0, last_line = cur_sec;
	long total = 0, total_lost = 0, other = 0, idle = 0;
	int have_cnt = 0; uint16_t last_cnt = 0;
	char ts[64], st[16];

	while (!stop_flag) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		int pr = poll(&pfd, 1, 100);
		if (pr < 0 && errno != EINTR) { perror("poll"); break; }
		time_t now = time(NULL);

		/* ---- a wall-clock second completed: one line for it ---- */
		if (now != cur_sec) {
			if (!first_t) {
				if (now - last_line >= IDLE_LINE_EVERY) {
					printf("%swaiting (no CSI yet: TX not started / channel or bandwidth mismatch?)\n", stamp(now, st, sizeof st)); last_line = now;
				}
			} else if (cur.n > 0 || idle < 2) {            /* show up to two "0 rec/s" lines after the stream stops */
				print_sec(now, &cur, total); last_line = now;
			} else if (now - last_line >= IDLE_LINE_EVERY) {
				printf("%sno CSI (TX stopped?)  total %ld\n", stamp(now, st, sizeof st), total); last_line = now;
			}
			idle = cur.n > 0 ? 0 : idle + 1;
			if (out) fflush(out);
			cur_sec = now; sec_reset(&cur);
		}

		/* ---- one record ---- */
		if (pr > 0) {
			if ((pfd.revents & (POLLHUP | POLLERR)) && !(pfd.revents & POLLIN)) break;   /* stdin stream ended */
			int l = next_record(fd, from_stdin, rec, nlbuf, sizeof nlbuf);
			if (l == 0) break;
			if (l < 0) continue;
			if (out) { uint16_t l_be = htons((uint16_t)l); fwrite(&l_be, 1, 2, out); fwrite(rec, 1, l, out); }
			if (rec[0] != CODE_BFEE || l < 1 + (int)sizeof(struct iwl_bfee_notif)) { other++; continue; }
			struct iwl_bfee_notif b; memcpy(&b, rec + 1, sizeof b);
			if (!first_t) {
				first_t = now;
				if (plain) printf("--- RX start (first CSI record) ---\n");
				else { fmt_time(now, DATETIME, ts, sizeof ts); printf("--- RX start %s (first CSI record) ---\n", ts); }
			}
			last_t = now; total++; cur.n++;
			cur.sa += (uint8_t)b.rssiA; cur.sb += (uint8_t)b.rssiB; cur.sc += (uint8_t)b.rssiC; cur.sagc += b.agc;
			double rss; if (total_rss_dbm(&b, &rss)) { cur.srss += rss; cur.nrss++; }
			if (cur.ntx < 0) { cur.ntx = b.Ntx; cur.nrx = b.Nrx; } else if (cur.ntx != b.Ntx || cur.nrx != b.Nrx) cur.mixed_shape = 1;
			if (cur.rate == 0xffff) cur.rate = b.fake_rate_n_flags; else if (cur.rate != b.fake_rate_n_flags) cur.mixed_rate = 1;
			if (have_cnt) { uint16_t d = (uint16_t)(b.bfee_count - last_cnt); if (d > 1 && d < 60000) { cur.lost += d - 1; total_lost += d - 1; } }
			last_cnt = b.bfee_count; have_cnt = 1;
		}
		if (secs > 0 && first_t && now - first_t >= secs) break;
	}
	time_t end = time(NULL);
	if (cur.n > 0) print_sec(end, &cur, total);           /* the partial last second */
	if (out) fclose(out);
	if (!from_stdin) close(fd);

	const char *why = stop_flag ? " (Ctrl-C / SIGTERM)" : (secs > 0 && first_t ? " (requested duration elapsed)" : (from_stdin ? " (stream ended)" : ""));
	if (plain) printf("--- RX end%s ---\n", why);
	else { fmt_time(end, DATETIME, ts, sizeof ts); printf("--- RX end %s%s ---\n", ts, why); }
	if (total) {
		char f[16], l[16]; fmt_time(first_t, "%H:%M:%S", f, sizeof f); fmt_time(last_t, "%H:%M:%S", l, sizeof l);
		double span = (double)(last_t - first_t) + 1.0;       /* whole seconds, inclusive */
		printf("received %ld CSI records / ~%.0f s = ~%.0f rec/s   lost (est., bfee_count gaps) %ld   first %s  last %s\n",
		       total, span, total / span, total_lost, f, l);
	} else printf("received 0 CSI records (nothing at all: check TX channel / bandwidth / rate, CSI firmware, connector_log)\n");
	if (other) printf("(also saved %ld non-CSI connector records)\n", other);
	if (outpath) printf("saved: %s (CSI-tool .csi format, readable by read_bf_file.m)\n", outpath);
	return 0;
}
