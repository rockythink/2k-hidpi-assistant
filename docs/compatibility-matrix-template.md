# HiDPIBuddy Compatibility Matrix Template

Use this file to record real display compatibility evidence. Keep one row per
display and connection path.

| Date | Mac | macOS | Display | Connection | Mode Enumeration | HiDPI Switch | Rollback | Apple Silicon DDC | Framebuffer DDC | DDC Read | DDC Write | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YYYY-MM-DD | Mac model / chip | 15.x | Vendor model | USB-C -> DP | pass/fail | pass/fail/not tested | pass/fail/not tested | available/unavailable | available/unavailable | pass/fail | pass/fail/not tested | Link to `diagnose --json` output |

## Required Evidence

- `swift run HiDPIBuddy diagnose --all --json`
- `swift run HiDPIBuddy ddc probe --all`
- HiDPI switch result with 15-second rollback behavior
- DDC write result only for brightness, contrast, or volume; include read-back
  verification status

## Unsupported Or Deferred

- EDID override is not part of default compatibility.
- Virtual display force-HiDPI is not part of default compatibility.
- VCP power mode and input source writes are not part of default compatibility.
