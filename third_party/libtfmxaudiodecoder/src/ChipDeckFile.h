// ChipDeck patch: open files by UTF-8 path on every platform.
// MSVC's std::ifstream(const std::string&) uses the ANSI code page, so
// names with accents or other non-ASCII letters would not open on Windows.
#ifndef CHIPDECKFILE_H
#define CHIPDECKFILE_H

#include <fstream>
#include <string>
#ifdef _WIN32
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#endif

namespace tfmxaudiodecoder {

inline void chipdeckOpen(std::ifstream& f, const std::string& utf8Path,
                         std::ios::openmode mode) {
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8Path.c_str(), -1, nullptr, 0);
    if (n > 0) {
        std::wstring w(static_cast<size_t>(n), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, utf8Path.c_str(), -1, &w[0], n);
        f.open(w.c_str(), mode);
        if (f.is_open()) return;
    }
#endif
    f.open(utf8Path.c_str(), mode);
}

}  // namespace

#endif
