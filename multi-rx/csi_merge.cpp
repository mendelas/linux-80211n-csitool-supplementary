// csi_merge: combine one or more csi_recv output files into one,
// sorted by control-PC time. Same record format in and out.
#include <cstdio>
#include <cstdint>
#include <vector>
#include <algorithm>
struct Rec { double t; uint8_t rx; uint16_t len; std::vector<uint8_t> pl; };
static bool read_rec(FILE* f, Rec& r) {
    if (fread(&r.t, sizeof(double), 1, f) != 1) return false;
    if (fread(&r.rx, 1, 1, f) != 1) return false;
    if (fread(&r.len, sizeof(uint16_t), 1, f) != 1) return false;
    r.pl.resize(r.len);
    return fread(r.pl.data(), 1, r.len, f) == r.len;
}
int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <out.bin> <in0.bin> [in1.bin ...]\n", argv[0]); return 1; }
    std::vector<Rec> all;
    for (int i = 2; i < argc; ++i) {
        FILE* f = fopen(argv[i], "rb"); if (!f) { perror(argv[i]); return 1; }
        Rec r; while (read_rec(f, r)) all.push_back(std::move(r));
        fclose(f);
    }
    std::stable_sort(all.begin(), all.end(), [](const Rec& a, const Rec& b){ return a.t < b.t; });
    FILE* o = fopen(argv[1], "wb"); if (!o) { perror("out"); return 1; }
    for (auto& r : all) {
        fwrite(&r.t, sizeof(double), 1, o);
        fwrite(&r.rx, 1, 1, o);
        fwrite(&r.len, sizeof(uint16_t), 1, o);
        fwrite(r.pl.data(), 1, r.len, o);
    }
    fclose(o);
    fprintf(stderr, "csi_merge: %zu records -> %s\n", all.size(), argv[1]);
    return 0;
}
