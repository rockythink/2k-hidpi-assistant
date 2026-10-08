# Display Resolution API References

HiDPIBuddy manages resolution only. Hardware controls, DDC probing, shading,
Night Shift, keyboard interception, display synchronization and scheduling are
not part of the application.

## References

- Chromium virtual display implementation:
  https://chromium.googlesource.com/chromium/src/+/d441ddf663e568fe8383d59a31e0dfacb9d9535b/ui/display/mac/test/virtual_display_mac_util.mm
  - `CGVirtualDisplayDescriptor.maxPixelsWide/High` are backing pixels.
  - With `settings.hiDPI = 1`, the mode initializer receives logical dimensions.
    For 1600×1000 points, advertise a 3200×2000 pixel descriptor and one
    1600×1000 mode. This relationship was verified on the local macOS 27.0 host.
- go-macos/virtualdisplay: https://github.com/go-macos/virtualdisplay/tree/279f8760a39881c35672fd4da6c1e5e87130e02d
  - Process lifetime matters: changing a virtual mode can prevent object
    release from removing the display until the creating process exits.
- hidpi-mirror: https://github.com/pasky/hidpi-mirror/tree/13acfaa0ec4b13bfce84554beebc8a09813cc2ae
  - Reference for virtual-source mirroring and private API compatibility risks.
  - Do not copy its doubled mode-initializer dimensions or main-display
    promotion policy: the local host needs Chromium's dimension relationship,
    and an unrelated main display must not be moved.
- BetterDisplay: https://github.com/waydabber/BetterDisplay
  - Product reference for native flexible scaling first and virtual mirroring as an optional fallback. Its application implementation is not provided by this documentation repository.
- Resolute: https://github.com/omar-hanafy/Resolute/tree/77a16d3f5340ef18cdc2456468b86850923d2729
  - MIT-licensed format reference for physical display scale-resolutions entries. HiDPIBuddy implements generation and the privileged transaction independently; no downloaded script is executed.
- vdisplay: https://github.com/pacifistazero/vdisplay/tree/0ce57c9c053cd918836098be8087d72b4775214f
  - Private virtual-display ABI reference; not a bundled dependency.
- Crisp: https://github.com/didriksg/Crisp/tree/a268173fa44b0b6d84fc9dafb20758097b60d07b
  - CGS mode-description ABI reference. Field offsets are protocol facts; this project implements its own byte decoding and mode selection.
  - The 8-byte physical-format candidate in PR 86 was inspected at https://github.com/dboleslawski/Crisp/tree/df02f3ddab0c6af5172af1ca5a98d9893a7d2a9e and independently validated on Sculptor.
- Historical Apple Silicon DDC implementation: see [third-party notices](../THIRD_PARTY_NOTICES.md). Hardware-control code has been removed from the current application; its historical license obligations remain.
## Native Mode Path

- Enumerate CGS private mode descriptions first, with public CoreGraphics modes
  as fallback; retain HiDPI and 1× variants and refresh-rate choices.
- Recommend only modes matching the physical native aspect ratio.
- Apply session changes first, then keep or restore through the App's
  15-second confirmation flow. Presets store resolution and refresh rate only.
- Missing modes never route automatically to a virtual display or privileged installation. A physical configuration requires an explicit confirmation and macOS administrator authorization.

## Physical Scaling Configuration

- Validated local path: unrotated online external2560×1600 panel →1600×1000 HiDPI. Write DisplayPixelDimensions as big-endian [2560,1600] UInt32, append only8-byte [3200,2000] render dimensions. Preserve unknown entries/fields; reject conflicting native dimensions. Do not generate the old16-byte [2W,2H,9,0x00A00000] marker or a defaultppmm.
- Merge one vendor/product plist in `/Library/Displays/Contents/Resources/Overrides`; `/System` is only a read-only template. Reject ambiguous matching arrays or inconsistent identities. A product override applies to every matching VID/PID, not an individual serial number.
- A root-owned receipt in `/Library/Application Support/HiDPIBuddy` stores the exact original bytes or absence, original panel dimensions, requested target and digests. Commit the receipt durably before the product file. Root-only writes, no-follow reads, path/ACL checks, a kernel lock and atomic rename protect the transaction.
- Restore only an unchanged installed product. Restore original bytes or delete that one product file if previously absent; never remove the vendor folder or sibling products. Concurrent edits or unsafe backups are conflicts, not permission to overwrite.
- A fixed inline transaction uses Apple `/usr/bin/ruby`, a sanitized environment and one `osascript` administrator authorization. Missing system Ruby fails before authorization; there is no Homebrew/PATH fallback. This deprecated system runtime is an explicit dependency.
- Installation does not prove mode registration. Reconnect/restart and refresh are separate user actions. Only an enumerated exact-2× mode enters the default selector, and physical panel coverage/refresh rate require hardware observation. Preserve the original panel dimensions so the added rendering companion is not mistaken for a larger physical panel.
- Temporary-sandbox transactions passed. On 2026-10-08 production installation and reconnection registered 1600×1000 at 120Hz/60Hz, with modes 91→93. The default selector preview reported 3200×2000 / 120Hz, two online displays, no mirror, and successful 15-second rollback, but physical acceptance FAILED: left/right black bars and vertically stretched text. The authorized production restore subsequently restored the previously absent product, leaving Sculptor 1280×800 / 120Hz and VX 2048×1152 / 60Hz unchanged. Cached modes may remain until reconnect. Hardware smoke sources were removed and the regular 35-test suite rebuilt successfully.
- Raw DCP NativeFormat remained1920×1080 after the separately authorized DisplayPixelDimensions2560×1600 trial. The trial was conservatively withdrawn without switching1600 under it, and the App selector/confirmation restored1280×800 /120Hz with VX unchanged. This does NOT prove CoreDisplay ignored the field: [Crisp PR86](https://github.com/didriksg/Crisp/pull/86) includes a maintainer report of normal smooth scaling with the same raw1920×1080 metadata on a5120×1440 panel. NativeFormat is not an independent high-level override acceptance test; the cause of the original distortion remains unresolved.
- CrispPR86 supplied the8-byte native-dimensions candidate but remains unmerged. Our authorized Sculptor trial passed independently: power off/on changed enumeration93→95, registered1600×1000 at120Hz/60Hz, and the same DisplayStore path previewed3200×2000 /120Hz with two online displays/no mirror. The user confirmed full panel coverage and normal text proportions;15-second rollback and subsequent keep/confirmation passed. The permanent generator now uses this format with existing installer revalidation/backup protections.36 regular tests passed and the App package was built/launched; actual main-window capture succeeded via OS window capture after native window helpers failed. Complete confirmation-sheet interaction remains unexercised because foreground control authorization timed out. No EDID edit or automatic physical reinitialization is used.

## Virtual Mode Path

- An Objective-C helper owns one virtual display. The Swift parent retains a
  stdin lifetime lease and consumes structured readiness / error messages.
- Create exactly one HiDPI mode and verify its actual CGS logical dimensions,
  density and refresh rate before establishing a virtual-source mirror.
- Let WindowServer choose the follower's scan-out mode. On the local host,
  pinning the physical standalone mode in the mirror transaction fails with
  CoreGraphics 1010. Position the virtual source only after mirroring.
- Use session-scoped transactions. Restore the target physical display's
  previous mode and origin; do not translate the whole desktop or promote the
  virtual source over an unrelated main display.
- Confirm only after the requested 2× mode and physical-to-virtual mirror are
  observed. Surface errors; do not report an unmirrored screen as success.
- Stop on timeout, explicit restore or normal application termination. Pipe
  EOF and a helper watchdog provide an abnormal-exit cleanup path. Strong-kill
  and unplug recovery remain untested on hardware.
- Refresh the App's physical display list on screen-parameter notifications,
  including after helper teardown. Do not retain removed virtual sidebar rows.

No EDID-byte changes, privileged drivers, permanent virtual sessions or automatic session recreation are installed. Physical scaling overrides are written only after explicit authorization; SIP remains enabled.
