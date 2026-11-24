// Disable LeakSanitizer at build time (leaks are not the bug class we fuzz for); ASan/UBSan stay on.
extern "C" int __lsan_is_turned_off() { return 1; }
