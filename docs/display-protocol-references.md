# Display Protocol References

This project should treat display compatibility as layered detection, not as a
single universal protocol.

## References

- MonitorControl: https://github.com/MonitorControl/MonitorControl
  - Useful for protocol layering: Apple native brightness, DDC/CI hardware
    control, gamma/shade fallback, virtual display handling.
  - Useful source areas: `Support/Arm64DDC.swift`, `Support/IntelDDC.swift`,
    display model classes, DDC preference handling.
- AppleSiliconDDC: https://github.com/waydabber/AppleSiliconDDC
  - Focused Apple Silicon DDC implementation.
  - Key idea: match `CGDirectDisplayID` to IORegistry framebuffer entries and
    `DCPAVServiceProxy`, then use `IOAVServiceReadI2C` / `IOAVServiceWriteI2C`.
- m1ddc: https://github.com/waydabber/m1ddc
  - Small Objective-C CLI for Apple Silicon DDC/CI over USB-C / DisplayPort Alt
    Mode. Good for packet layout and CLI diagnostics.
- BetterDisplay: https://github.com/waydabber/BetterDisplay
  - Product reference for HiDPI scaling, virtual screens, EDID overrides, DDC,
    and display configuration boundaries.
- one-key-hidpi: https://github.com/xzhih/one-key-hidpi
  - EDID override route. Useful as background, but should remain outside the
    default product path because it modifies system display overrides and can
    require recovery steps.
- force-hidpi: https://github.com/sammcj/force-hidpi
  - Virtual-display workaround route for Apple Silicon 4K HiDPI regressions.
    Useful for understanding `CGVirtualDisplay`, mirroring, color profile
    matching, and DCP pixel-budget limits.

## Adoption Boundary

Keep the default HiDPIBuddy path conservative:

- Enumerate and switch only real modes currently exposed by macOS.
- Diagnose missing HiDPI targets instead of silently forcing EDID overrides.
- Add protocol backends behind explicit capability detection.
- Prefer read-only diagnostics before enabling hardware DDC writes.

## Implementation Notes

- Current HiDPI mode enumeration uses CGS private mode descriptions first, with
  CoreGraphics public modes as fallback.
- Existing DDC control uses `CGDisplayIOServicePort` and
  `IOFBGetI2CInterfaceCount`, which is closer to the traditional framebuffer
  path.
- Apple Silicon compatibility should add a separate IORegistry /
  `DCPAVServiceProxy` path, based on MonitorControl and AppleSiliconDDC.
- Compatibility reports should include display metadata, mode source, transport
  candidates, match score, and whether an external `DCPAVServiceProxy` exists.
