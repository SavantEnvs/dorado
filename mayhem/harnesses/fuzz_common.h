// Shared helpers for dorado fuzz harnesses.
#pragma once
#include <spdlog/spdlog.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

namespace dorado_fuzz {

// Logging is process-global, read-only after init: silence it once (same for every input).
inline void silence_logging() { spdlog::set_level(spdlog::level::off); }

inline std::string tmp_dir() {
    const char* t = std::getenv("TMPDIR");
    return (t && *t) ? std::string(t) : std::string("/tmp");
}

// Writes the input to a fresh mkstemps() file with the given suffix; returns its path ("" on failure).
inline std::string write_temp(const uint8_t* data, size_t size, const char* suffix) {
    std::string path = tmp_dir() + "/dorado_fuzz_XXXXXX" + suffix;
    int fd = mkstemps(path.data(), (int)std::string(suffix).size());
    if (fd < 0) return "";
    size_t off = 0;
    while (off < size) {
        ssize_t n = write(fd, data + off, size - off);
        if (n <= 0) break;
        off += (size_t)n;
    }
    close(fd);
    return path;
}

}  // namespace dorado_fuzz
