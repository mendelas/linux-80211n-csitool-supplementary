// read_merged: minimal C++ reader for the merged file (downstream entry point).
// Record: [double t][uint8 rx_id][uint16 len][len bytes payload]
// payload[0] == 0xbb  => CSI/BFEE record (parse with the CSI tool bfee format).
#include <cstdio>
#include <cstdint>
#include <vector>
int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <merged.bin>\n", argv[0]); return 1; }
    FILE* f = fopen(argv[1], "rb"); if (!f) { perror("open"); return 1; }
    double t; uint8_t rx; uint16_t len; std::vector<uint8_t> pl; long n = 0;
    while (fread(&t, sizeof(double), 1, f) == 1) {
        if (fread(&rx, 1, 1, f) != 1) break;
        if (fread(&len, sizeof(uint16_t), 1, f) != 1) break;
        pl.resize(len);
        if (fread(pl.data(), 1, len, f) != len) break;
        uint8_t code = len ? pl[0] : 0;   // 0xbb = CSI
        if (n < 10) printf("t=%.6f  rx=%u  len=%u  code=0x%02x\n", t, rx, len, code);
        ++n;
    }
    printf("total %ld records\n", n);
    fclose(f);
    return 0;
}
