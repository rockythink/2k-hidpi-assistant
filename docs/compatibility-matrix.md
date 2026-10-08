# HiDPIBuddy Compatibility Matrix

Only resolution-related behavior is in scope. Connection paths not observed
in the current session are marked unknown rather than inferred.

| Date | Mac / macOS | Display | Connection | Mode Enumeration | Native HiDPI | Virtual HiDPI | Recovery | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-07 | Apple Silicon / 27.0 (26A428) | Sculptor, 2560×1600, vendor 0x6474 product 0xD01F | unknown | 91 modes / 52 HiDPI before virtual creation | 1280×800 @ 120Hz switch and confirmation passed | 1440×900, 1600×1000, 1680×1050, 1920×1200 @ 60Hz, exact 2× buffers passed | 15-second timeout, manual stop and normal App quit passed; original 1680×1050 @ 60Hz 1× and origin (2048,465) restored | Actual App UI and fresh CLI observations; virtual sessions not persisted. |
| 2026-10-07 | Apple Silicon / 27.0 (26A428) | VX2462-2K, main display #3 | unknown | current 2048×1152 @ 60Hz HiDPI observed | existing current mode retained | not activated on this screen | mode and origin (0,0) unchanged throughout target-screen tests | Resolution preset save/apply/delete also passed without changing this screen or deleting the existing user preset. |
| 2026-10-08 | Apple Silicon / 27.0.1 (26A434) | Sculptor, 2560×1600, vendor0x6474 product0xD01F | DP → HDMI (IORegistry) | 93→95 after8-byte configuration and monitor power off/on; registry entry ID stayed stable | 1600×1000 HiDPI /120Hz, framebuffer3200×2000; user confirmed full coverage and normal text; kept | not activated; two online displays, no mirror | 15-second automatic rollback, subsequent confirmation/keep, production configuration restore passed | Old16-byte-marked trial distorted output; permanent generation now8-byte plus native dimensions. Main mode unchanged during each switch; final fresh VX observation1920×1080/60Hz is retained, not overwritten. |
| 2026-06-26 | Apple Silicon / historical local macOS | VX2462-2K, vendor 0x5A63 product 0xC93C | DP → HDMI (historical report) | 113 modes / 63 HiDPI (historical report) | 1920×1080 @ 75Hz HiDPI (historical report) | not tested | previously recorded App rollback | Historical observation only; not rerun or asserted as current behavior. |

## Evidence

Current observations were collected through the App's native accessibility
surface / screenshots and `HiDPIBuddy diagnose --all --json`. Session-local
diagnostic records and screenshots are not committed fixtures or downloadable
evidence.

The regular suite passed 36 tests, including binary dimension contracts,
conflict rejection and real unprivileged sandbox transactions. Authorized
production installation/restoration and default-selector previews exercised
real hardware; their temporary sources were removed and the suite rebuilt.
Physical output at 1600×1000 was user-verified, then kept. The App bundle was
built and launched, and its actual main window was captured. Complete
confirmation-sheet interaction remains unexercised. Framebuffers are render
dimensions, not extra physical panel pixels.

## Not Verified

- Other devices/OS versions and reboot activation of the8-byte format. Local Sculptor1600×1000 full coverage/text proportions,120Hz and no-mirror output passed; initial16-byte failure and native-dimensions-only uncertainty remain historical results, not the current path.
- Virtual refresh rates above 60Hz.
- Forced App termination or display unplugging while mirrored.
- Other macOS versions / Intel Macs, built-in or rotated displays.
- Third-party virtual displays, AirPlay, Sidecar and DisplayLink.
