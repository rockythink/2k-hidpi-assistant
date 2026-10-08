# PixelFit Compatibility Matrix

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
surface / screenshots and `PixelFit diagnose --all --json`. Session-local
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

The PixelFit rebrand passed all 36 tests, packaged App launch, CLI help and the
renamed helper's non-mutating runtime check. Native main-window and About-panel
observations confirmed the PixelFit title, application menu and new geometric
icon. Sculptor remained at 1600×1000 HiDPI / 120Hz with a 3200×2000 framebuffer,
no mirror, and the existing installed configuration still registered/restorable.
The VX main window continued to show 1920×1080 HiDPI / 60Hz. The bundle identity
and original state/receipt paths are intentionally unchanged; no display mode
or privileged configuration was written during branding verification.

PixelFit 0.2.0 also exercised duplicate GUI startup: a second direct invocation
returned successfully while the existing GUI PID remained unchanged, and the
legacy HiDPIBuddy process was absent. Diagnostic CLI continued to work while
the GUI was running. The signed arm64 release used Developer ID Application,
hardened runtime and secure timestamps for both the App and helper; its actual
main window was captured. This check did not change the Sculptor mode or its
installed/restorable physical configuration.

Apple notarization accepted the final PixelFit 0.2.0 arm64 App under submission
`a2f5efd0-5c73-492e-bce4-d8066f8cee0a`. Stapling and ticket validation passed;
strict signature verification passed; Gatekeeper reported `accepted` with
source `Notarized Developer ID`. The distributable ZIP was recreated after
stapling, with a separate SHA-256 checksum file.

## Not Verified

- Other devices/OS versions and reboot activation of the8-byte format. Local Sculptor1600×1000 full coverage/text proportions,120Hz and no-mirror output passed; initial16-byte failure and native-dimensions-only uncertainty remain historical results, not the current path.
- Virtual refresh rates above 60Hz.
- Forced App termination or display unplugging while mirrored.
- Other macOS versions / Intel Macs, built-in or rotated displays.
- Third-party virtual displays, AirPlay, Sidecar and DisplayLink.
