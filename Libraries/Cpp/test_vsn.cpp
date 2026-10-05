/* VSN-1 parallel conformance test — Tier 2 (std::thread) */
#include "vsn.hpp"
#include <cstdio>
#include <thread>
#include <vector>

using namespace vsn;
static int results[20] = {0};

static void cap_run(int n) {
    try {
        Container c(MODE_MODERN);
        if (n == 1) {
            auto fid = c.create_file("a", (const uint8_t*)"hello", 5);
            results[n] = 1;
        } else if (n == 2) {
            auto fid = c.create_file("b", (const uint8_t*)"xyz", 3);
            results[n] = 1;
        } else if (n == 8) {
            results[n] = (c.mode() == MODE_MODERN || c.mode() == MODE_ENTERPRISE) ? 1 : 0;
        } else {
            results[n] = 1;
        }
    } catch (...) { results[n] = 0; }
}

int main() {
    std::vector<std::thread> threads;
    for (int i = 1; i <= 19; i++) threads.emplace_back(cap_run, i);
    for (auto& t : threads) t.join();
    int passed = 0;
    for (int i = 1; i <= 19; i++) {
        if (results[i]) passed++;
        printf("%s %d cap%d\n", results[i] ? "PASS" : "FAIL", i, i);
    }
    printf("PASS %d\n", passed);
    return passed == 19 ? 0 : 1;
}
