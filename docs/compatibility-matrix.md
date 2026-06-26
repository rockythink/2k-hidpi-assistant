# HiDPIBuddy Compatibility Matrix

| Date | Mac | macOS | Display | Connection | Mode Enumeration | HiDPI Switch | Rollback | Apple Silicon DDC | Framebuffer DDC | DDC Read | DDC Write | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-06-26 | Current Apple Silicon Mac | Current local macOS | VX2462-2K / vendor 0x5A63 product 0xC93C | DP -> HDMI | pass: 113 modes, 63 HiDPI | pass: current 1920 x 1080 @ 75Hz HiDPI | previously verified by app rollback flow | pass: external DCPAVServiceProxy, score 5 | unavailable: no framebuffer service | pass: brightness 100/100, contrast 70/100, volume 47/100 | pass: brightness 100 -> 100 verified | Evidence: `/tmp/hidpibuddy-diagnose.json`, `/tmp/hidpibuddy-ddc-probe.txt` |
| pending | Apple Silicon Mac | pending | Built-in display | Built-in | pending | pending | pending | not expected | not expected | pending | not planned | Verify Apple native brightness path. |
| pending | Apple Silicon Mac | pending | External 2K/2.5K display | USB-C / DisplayPort | pending | pending | pending | pending | pending | pending | pending | Needed to compare direct DP against DP -> HDMI adapter. |
| pending | Apple Silicon Mac | pending | External 4K display | HDMI | pending | pending | pending | pending | pending | pending | pending | Needed to check Apple Silicon HDMI DDC limitations. |
| pending | Apple Silicon Mac | pending | Virtual / DisplayLink / AirPlay / Sidecar | Virtual or docked | pending | pending | pending | expected unavailable | expected unavailable | pending | not planned | Should degrade to software/no hardware control messaging. |
