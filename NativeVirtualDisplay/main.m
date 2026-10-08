#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>

// Runtime declarations only. ABI evidence:
// github.com/pasky/hidpi-mirror/blob/main/hidpi-mirror.m
// github.com/pacifistazero/vdisplay/blob/main/Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h
// Private classes are checked at runtime; none are linked by class symbol.
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, retain) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic, copy) void (^terminationHandler)(id, id);
- (void)setQueue:(dispatch_queue_t)queue;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end
@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static CGVirtualDisplay *virtualDisplay;
static CGDirectDisplayID physicalID, virtualID;
static CGDisplayModeRef previousMode;
static CGPoint previousOrigin;
static unsigned int logicalWidth, logicalHeight;
static BOOL stopping, mirrorSubmitted, ready;
static pid_t parentPID;
static double requestedRate;
static unsigned int settleTicks;

static void emit(NSDictionary *value) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if (!data) { fprintf(stderr, "JSON encoding failed: %s\n", error.localizedDescription.UTF8String); return; }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *cgFailure(NSString *operation, CGError error) {
    return [NSString stringWithFormat:@"%@ failed (CoreGraphics %d)", operation, error];
}

// Only touch our follower. In particular never translate the whole desktop or
// promote a virtual display over an unrelated main screen.
static NSString *restorePhysical(void) {
    if (!previousMode || !CGDisplayIsOnline(physicalID)) return nil;
    CGDirectDisplayID source = CGDisplayMirrorsDisplay(physicalID);
    if (source != kCGNullDirectDisplay && source != virtualID) {
        return @"Display joined another mirror set; refusing to alter that configuration";
    }
    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess) return cgFailure(@"Begin restore", error);
    if (source == virtualID && virtualID != 0) {
        error = CGConfigureDisplayMirrorOfDisplay(config, physicalID, kCGNullDirectDisplay);
    }
    if (error == kCGErrorSuccess) error = CGConfigureDisplayWithDisplayMode(config, physicalID, previousMode, NULL);
    if (error == kCGErrorSuccess) error = CGConfigureDisplayOrigin(config, physicalID, (int32_t)previousOrigin.x, (int32_t)previousOrigin.y);
    if (error != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return cgFailure(@"Configure restore", error);
    }
    error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    return error == kCGErrorSuccess ? nil : cgFailure(@"Complete restore", error);
}

static void finish(NSString *failure) {
    if (stopping) return;
    stopping = YES;
    NSString *restoreError = restorePhysical();
    @try { virtualDisplay = nil; } @catch (NSException *exception) {
        restoreError = exception.reason ?: @"Private display teardown threw an exception";
    }
    virtualID = 0;
    if (previousMode) { CFRelease(previousMode); previousMode = NULL; }
    if (failure || restoreError) {
        NSString *message = failure && restoreError ? [NSString stringWithFormat:@"%@; %@", failure, restoreError] : (failure ?: restoreError);
        emit(@{@"event": @"error", @"message": message});
        exit(1);
    }
    emit(@{@"event": @"stopped"});
    exit(0);
}

// Verify actual mode dimensions using the same CGS ABI as CGSDisplayModeAPI.swift.
extern CGError CGSGetNumberOfDisplayModes(CGDirectDisplayID, int32_t *);
extern CGError CGSGetCurrentDisplayMode(CGDirectDisplayID, int32_t *);
extern CGError CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID, int32_t, void *, int32_t);

static int32_t wantedModeNumber(double *rate, BOOL *active) {
    int32_t count = 0, current = -1;
    if (CGSGetNumberOfDisplayModes(virtualID, &count) != kCGErrorSuccess || count <= 0) return -1;
    CGSGetCurrentDisplayMode(virtualID, &current);
    for (int32_t index = 0; index < count; index++) {
        uint8_t bytes[256] = {0};
        if (CGSGetDisplayModeDescriptionOfLength(virtualID, index, bytes, sizeof(bytes)) != kCGErrorSuccess) continue;
        uint32_t number, width, height; float density; uint16_t hz;
        memcpy(&number, bytes, 4); memcpy(&width, bytes + 8, 4); memcpy(&height, bytes + 12, 4);
        memcpy(&density, bytes + 208, 4); memcpy(&hz, bytes + 190, 2);
        if (width == logicalWidth && height == logicalHeight && fabsf(density - 2) < 0.01 && hz > 0) {
            *rate = hz; *active = current == (int32_t)number; return (int32_t)number;
        }
    }
    return -1;
}


static void settle(void) {
    if (getppid() != parentPID) { finish(nil); return; }
    if (!CGDisplayIsOnline(physicalID)) { finish(@"Physical display disconnected"); return; }
    if (ready) {
        if (CGDisplayMirrorsDisplay(physicalID) != virtualID) finish(@"Virtual mirror was removed by the system");
        return;
    }
    double rate = 0;
    BOOL exact = NO;
    int32_t wanted = wantedModeNumber(&rate, &exact);
    if (mirrorSubmitted && exact && CGDisplayMirrorsDisplay(physicalID) == virtualID && rate > 0) {
        CGPoint origin = CGDisplayBounds(virtualID).origin;
        if (origin.x != previousOrigin.x || origin.y != previousOrigin.y) {
            // Position only after mirroring; do not combine mode and mirror changes.
            CGDisplayConfigRef config = NULL;
            CGError error = CGBeginDisplayConfiguration(&config);
            if (error == kCGErrorSuccess) {
                error = CGConfigureDisplayOrigin(config, virtualID, (int32_t)previousOrigin.x, (int32_t)previousOrigin.y);
                if (error == kCGErrorSuccess) error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
                else CGCancelDisplayConfiguration(config);
            }
            if (error != kCGErrorSuccess) { finish(cgFailure(@"Restore mirror position", error)); return; }
        }
        ready = YES;
        emit(@{@"event": @"ready", @"displayID": @(physicalID), @"virtualDisplayID": @(virtualID),
            @"width": @(logicalWidth), @"height": @(logicalHeight), @"pixelWidth": @(2 * logicalWidth),
            @"pixelHeight": @(2 * logicalHeight), @"refreshRate": @(rate)});
        return;
    }
    if (++settleTicks > 80) {
        finish(@"WindowServer did not activate the exact 2× HiDPI mode and virtual-source mirror");
        return;
    }
    if (!mirrorSubmitted && exact && wanted >= 0) {
        // Let WindowServer choose the physical scan-out mode for the mirror.
        // Pinning its standalone mode in the same transaction is invalid.
        NSString *operation = @"Begin mirror configuration";
        CGDisplayConfigRef config = NULL;
        CGError error = CGBeginDisplayConfiguration(&config);
        if (error == kCGErrorSuccess) {
            if (error == kCGErrorSuccess) { operation = @"Set virtual-source mirror"; error = CGConfigureDisplayMirrorOfDisplay(config, physicalID, virtualID); }
            if (error == kCGErrorSuccess) { operation = @"Commit virtual-source mirror"; error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession); }
            else CGCancelDisplayConfiguration(config);
        }
        if (error != kCGErrorSuccess) { finish(cgFailure(operation, error)); return; }
        mirrorSubmitted = YES;
    }
}

static NSString *validateABI(void) {
    NSDictionary<NSString *, NSArray<NSString *> *> *requirements = @{
        @"CGVirtualDisplay": @[@"initWithDescriptor:", @"applySettings:", @"displayID"],
        @"CGVirtualDisplayMode": @[@"initWithWidth:height:refreshRate:"],
        @"CGVirtualDisplaySettings": @[@"setModes:", @"setHiDPI:"],
        @"CGVirtualDisplayDescriptor": @[@"setName:", @"setSizeInMillimeters:", @"setMaxPixelsWide:", @"setMaxPixelsHigh:",
            @"setVendorID:", @"setProductID:", @"setSerialNum:", @"setTerminationHandler:",
            @"setRedPrimary:", @"setGreenPrimary:", @"setBluePrimary:", @"setWhitePoint:"]
    };
    for (NSString *name in requirements) {
        Class cls = NSClassFromString(name);
        if (!cls) return [NSString stringWithFormat:@"%@ is unavailable on macOS %@", name, NSProcessInfo.processInfo.operatingSystemVersionString];
        for (NSString *selector in requirements[name]) {
            if (![cls instancesRespondToSelector:NSSelectorFromString(selector)]) return [NSString stringWithFormat:@"Private API %@.%@ is unavailable", name, selector];
        }
    }
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    if (![descriptor instancesRespondToSelector:@selector(setQueue:)] && ![descriptor instancesRespondToSelector:@selector(setDispatchQueue:)]) return @"Private display dispatch queue API is unavailable";
    return nil;
}

static BOOL parseUnsigned(const char *argument, unsigned int *value) {
    char *end = NULL;
    errno = 0;
    unsigned long result = strtoul(argument, &end, 10);
    if (errno || !argument[0] || *end || result > UINT_MAX) return NO;
    *value = (unsigned int)result;
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (argc == 2 && strcmp(argv[1], "--help") == 0) {
            puts("PixelFitVirtualDisplayHelper DISPLAY_ID LOGICAL_WIDTH LOGICAL_HEIGHT REFRESH_HZ\nPrivate CGVirtualDisplay helper. JSON lines on stdout; stdin EOF stops and restores the targeted display.\n--version performs only runtime ABI checks; no display is created.");
            return 0;
        }
        // Restore is isolated in a disposable process because a display
        // transaction can block indefinitely during hot-unplug. No private API.
        if (argc == 6 && strcmp(argv[1], "--restore") == 0) {
            unsigned int modeID = 0;
            char *xEnd = NULL, *yEnd = NULL;
            long x = strtol(argv[4], &xEnd, 10), y = strtol(argv[5], &yEnd, 10);
            if (!parseUnsigned(argv[2], &physicalID) || !parseUnsigned(argv[3], &modeID) || *xEnd || *yEnd || x < INT32_MIN || x > INT32_MAX || y < INT32_MIN || y > INT32_MAX) {
                emit(@{@"event": @"error", @"message": @"Invalid restore snapshot"}); return 1;
            }
            if (!CGDisplayIsOnline(physicalID)) { emit(@{@"event": @"stopped"}); return 0; }
            if (CGDisplayIsInMirrorSet(physicalID)) {
                emit(@{@"event": @"error", @"message": @"Target is still mirrored; refusing to alter another mirror set"}); return 1;
            }
            previousOrigin = CGPointMake(x, y);
            NSDictionary *options = @{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES};
            CFArrayRef modes = CGDisplayCopyAllDisplayModes(physicalID, (__bridge CFDictionaryRef)options);
            if (modes) {
                for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
                    CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                    if (CGDisplayModeGetIODisplayModeID(mode) == modeID) { previousMode = (CGDisplayModeRef)CFRetain(mode); break; }
                }
                CFRelease(modes);
            }
            if (!previousMode) { emit(@{@"event": @"error", @"message": @"Previous physical display mode is no longer available"}); return 1; }
            NSString *failure = restorePhysical();
            CFRelease(previousMode); previousMode = NULL;
            emit(failure ? @{@"event": @"error", @"message": failure} : @{@"event": @"stopped"});
            return failure ? 1 : 0;
        }
        NSString *abiError = validateABI();
        if (argc == 2 && strcmp(argv[1], "--version") == 0) {
            emit(@{@"version": @1, @"privateAPIAvailable": @(!abiError), @"message": abiError ?: @"CGVirtualDisplay runtime selectors available"});
            return abiError ? 1 : 0;
        }
        if (abiError) { emit(@{@"event": @"error", @"message": abiError}); return 1; }
        if (argc != 5 || !parseUnsigned(argv[1], &physicalID) || !parseUnsigned(argv[2], &logicalWidth) || !parseUnsigned(argv[3], &logicalHeight) || physicalID == 0 || logicalWidth == 0 || logicalHeight == 0) {
            emit(@{@"event": @"error", @"message": @"Expected DISPLAY_ID LOGICAL_WIDTH LOGICAL_HEIGHT REFRESH_HZ"}); return 1;
        }
        char *end = NULL;
        requestedRate = strtod(argv[4], &end);
        if (*end || !isfinite(requestedRate) || requestedRate < 24 || requestedRate > 240 || logicalWidth > 4096 || logicalHeight > 4096) {
            emit(@{@"event": @"error", @"message": @"Unsupported dimensions or refresh rate"}); return 1;
        }
        if (!CGDisplayIsOnline(physicalID) || CGDisplayIsBuiltin(physicalID) || CGDisplayIsInMirrorSet(physicalID) || fabs(CGDisplayRotation(physicalID)) > 0.01) {
            emit(@{@"event": @"error", @"message": @"Target must be online, external, unrotated, and outside any mirror set"}); return 1;
        }
        parentPID = getppid();
        previousMode = CGDisplayCopyDisplayMode(physicalID);
        previousOrigin = CGDisplayBounds(physicalID).origin;
        if (!previousMode) { emit(@{@"event": @"error", @"message": @"Could not capture the previous physical display mode"}); return 1; }
        // Read the lease off the main queue: CoreGraphics transactions may
        // stall there. After EOF, allow normal restore, then force process
        // destruction even if WindowServer never returns from a transaction.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buffer[64];
            ssize_t count;
            do { count = read(STDIN_FILENO, buffer, sizeof(buffer)); } while (count > 0 || (count < 0 && errno == EINTR));
            NSString *failure = count < 0 ? @"Stdin lifetime lease failed" : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ finish(failure); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ _exit(2); });
        });
        @try {
            CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
            if ([descriptor respondsToSelector:@selector(setQueue:)]) [descriptor setQueue:dispatch_get_main_queue()];
            else [descriptor setDispatchQueue:dispatch_get_main_queue()];
            descriptor.name = @"PixelFit Virtual HiDPI";
            descriptor.maxPixelsWide = logicalWidth * 2;
            descriptor.maxPixelsHigh = logicalHeight * 2;
            CGSize size = CGDisplayScreenSize(physicalID);
            descriptor.sizeInMillimeters = size.width > 0 && size.height > 0 ? size : CGSizeMake(logicalWidth * 0.254, logicalHeight * 0.254);
            descriptor.vendorID = 0x4844;
            // WindowServer remembers preferred modes by vendor/product, not only serial.
            descriptor.productID = arc4random_uniform(65534) + 1;
            descriptor.serialNum = arc4random_uniform(UINT_MAX - 1) + 1;
            descriptor.redPrimary = CGPointMake(0.64, 0.33);
            descriptor.greenPrimary = CGPointMake(0.30, 0.60);
            descriptor.bluePrimary = CGPointMake(0.15, 0.06);
            descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
            descriptor.terminationHandler = ^(id reason, id display) {
                if (!stopping) finish(@"WindowServer terminated the virtual display");
            };
            virtualDisplay = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
            if (!virtualDisplay || !(virtualID = virtualDisplay.displayID)) { finish(@"Private API could not create a virtual display"); return 1; }
            CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
            settings.hiDPI = 1;
            // With hiDPI enabled, the mode takes logical points; the descriptor
            // takes backing pixels (Chromium virtual_display_mac_util.mm).
            CGVirtualDisplayMode *mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:logicalWidth height:logicalHeight refreshRate:requestedRate];
            if (!mode) { finish(@"Private API could not create the preferred HiDPI mode"); return 1; }
            settings.modes = @[mode];
            if (![virtualDisplay applySettings:settings]) { finish(@"Private API refused the HiDPI settings"); return 1; }
        } @catch (NSException *exception) {
            finish([NSString stringWithFormat:@"Private API exception %@: %@", exception.name, exception.reason]);
            return 1;
        }
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        dispatch_source_t terminate = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_t interrupt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(terminate, ^{ finish(nil); });
        dispatch_source_set_event_handler(interrupt, ^{ finish(nil); });
        dispatch_resume(terminate);
        dispatch_resume(interrupt);
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 4, NSEC_PER_MSEC * 20);
        dispatch_source_set_event_handler(timer, ^{ @try { settle(); } @catch (NSException *exception) { finish(exception.reason ?: @"Private API exception"); } });
        dispatch_resume(timer);
        dispatch_main();
    }
}
