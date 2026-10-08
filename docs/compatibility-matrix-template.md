# HiDPIBuddy Compatibility Matrix Template

Record actual resolution behavior, one row per physical display and connection
path. Use `not tested` for unexercised behavior and `unknown` for missing
hardware information.

| Date | Mac / macOS | Display | Connection | Mode Enumeration | Native HiDPI | Virtual HiDPI | Recovery | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YYYY-MM-DD | Model / chip / OS build | Vendor / product / native dimensions | Observed cable / adapter, or unknown | Count / source | Logical + pixel dimensions / Hz, pass or fail | Target / 2× buffer / actual Hz / mirror IDs, pass or fail | Timeout / manual stop / quit, pass or fail | Unrelated screen mode and origin; evidence |

## Required Evidence

- `swift run HiDPIBuddy diagnose --all --json` before, during and after switching.
- Actual App UI observations; do not treat an advertised mode as proof of a
  successful switch.
- For virtual sessions: exact logical and pixel dimensions, actual refresh
  rate, and the physical follower's source display ID.
- The exercised confirmation and recovery paths, including restored physical
  mode and origin, removal of the virtual display, and unchanged unrelated
  screens.
- If testing abnormal exit or unplugging, report the actual result separately
  from normal App quit. Do not claim those paths from source inspection alone.

## Outside Scope

- EDID overrides, privileged drivers and SIP changes.
- Brightness, volume, contrast, input source, power and DDC control.
- Persisted virtual sessions or automatic recreation after launch.
