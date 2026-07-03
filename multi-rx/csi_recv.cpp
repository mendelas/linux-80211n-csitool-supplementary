// csi_recv: read a CSI byte stream on stdin (from csi_stream over SSH),
// stamp each record with the control-PC monotonic clock, append to <out.bin>.
// Record framing in:  [uint16 BE len][len bytes payload]
// Record framing out: [double t_mono][uint8 rx_id][uint16 len][len bytes payload]
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <arpa/inet.h>   // ntohs
#include <time.h>
#include <unistd.h>

static int read_full(int fd, void* buf, size_t n) {
    uint8_t* p = (uint8_t*)buf; size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, p + got, n - got);
        if (r <= 0) return (int)got;      // EOF / error
        got += (size_t)r;
    }
    return (int)got;
}

int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <rx_id> <out.bin>\n", argv[0]); return 1; }
    uint8_t rx_id = (uint8_t)atoi(argv[1]);
    FILE* out = fopen(argv[2], "wb");
    if (!out) { perror("fopen out"); return 1; }
    uint8_t payload[4096];
    long count = 0;
    while (1) {
        uint16_t l_be;
        if (read_full(0, &l_be, 2) != 2) break;            // stream ended
        uint16_t l = ntohs(l_be);
        if (l == 0 || l > sizeof(payload)) { fprintf(stderr, "csi_recv: bad len %u\n", l); break; }
        if (read_full(0, payload, l) != (int)l) break;
        struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
        double t = (double)ts.tv_sec + ts.tv_nsec * 1e-9;   // control-PC relative time
        fwrite(&t, sizeof(double), 1, out);
        fwrite(&rx_id, 1, 1, out);
        fwrite(&l, sizeof(uint16_t), 1, out);
        fwrite(payload, 1, l, out);
        fflush(out);                                        // land on disk promptly
        ++count;
    }
    fclose(out);
    fprintf(stderr, "csi_recv: rx%u wrote %ld records to %s\n", rx_id, count, argv[2]);
    return 0;
}
