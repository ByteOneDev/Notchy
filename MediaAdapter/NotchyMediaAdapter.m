// NotchyMediaAdapter
// Since macOS 15.4, MediaRemote only answers Apple-signed processes. This dylib is loaded by
// /usr/bin/perl (an Apple platform binary) through DynaLoader, streams the now playing state
// to stdout as JSON lines and reads playback commands from stdin.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientStringFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetClientFn MRGetClient;
static MRClientStringFn MRClientBundleID;
static MRClientStringFn MRClientParentBundleID;
static MRRegisterFn MRRegister;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;

static NSUInteger lastArtworkHash = 0;
static BOOL refreshScheduled = NO;

static void emit(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id jsonSafe(id value) {
    if (!value) return [NSNull null];
    if ([value isKindOfClass:[NSDate class]]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    return [NSNull null];
}

static void refresh(void) {
    refreshScheduled = NO;
    dispatch_queue_t q = dispatch_get_main_queue();
    MRGetClient(q, ^(id client) {
        NSString *bundleID = client && MRClientBundleID ? MRClientBundleID(client) : nil;
        NSString *parentID = client && MRClientParentBundleID ? MRClientParentBundleID(client) : nil;
        MRGetIsPlaying(q, ^(Boolean playing) {
            MRGetInfo(q, ^(NSDictionary *info) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"type"] = @"state";
                out[@"playing"] = @(playing);
                out[@"bundleID"] = jsonSafe(bundleID);
                out[@"parentBundleID"] = jsonSafe(parentID);
                out[@"title"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
                out[@"artist"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                out[@"album"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                out[@"duration"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                out[@"elapsed"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                out[@"rate"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                out[@"timestamp"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoTimestamp"]);
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
                    NSUInteger hash = artwork.hash ^ artwork.length;
                    out[@"artworkID"] = @(hash);
                    if (hash != lastArtworkHash) {
                        out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                        lastArtworkHash = hash;
                    }
                } else {
                    out[@"artworkID"] = @0;
                    lastArtworkHash = 0;
                }
                emit(out);
            });
        });
    });
}

static void scheduleRefresh(void) {
    if (refreshScheduled) return;
    refreshScheduled = YES;
    // Coalesce bursts of notifications (a track change fires several at once).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ refresh(); });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    // MRMediaRemoteCommand values
    if ([cmd isEqualToString:@"play"]) MRSendCommand(0, nil);
    else if ([cmd isEqualToString:@"pause"]) MRSendCommand(1, nil);
    else if ([cmd isEqualToString:@"toggle"]) MRSendCommand(2, nil);
    else if ([cmd isEqualToString:@"next"]) MRSendCommand(4, nil);
    else if ([cmd isEqualToString:@"previous"]) MRSendCommand(5, nil);
    else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
    else if ([cmd isEqualToString:@"refresh"]) lastArtworkHash = 0;
    scheduleRefresh();
}

static BOOL loadMediaRemote(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) return NO;
    MRGetInfo = (MRGetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    MRGetIsPlaying = (MRGetIsPlayingFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClient = (MRGetClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingClient");
    MRClientBundleID = (MRClientStringFn)dlsym(h, "MRNowPlayingClientGetBundleIdentifier");
    MRClientParentBundleID = (MRClientStringFn)dlsym(h, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MRRegister = (MRRegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MRSendCommand = (MRSendCommandFn)dlsym(h, "MRMediaRemoteSendCommand");
    MRSetElapsed = (MRSetElapsedFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    return MRGetInfo && MRGetIsPlaying && MRGetClient && MRRegister && MRSendCommand;
}

// Called from perl as an XSUB: void(pTHX_ CV *). Never returns.
__attribute__((visibility("default")))
void notchy_media_stream(void *interp, void *cv) {
    @autoreleasepool {
        if (!loadMediaRemote()) {
            emit(@{ @"type": @"error", @"message": @"MediaRemote unavailable" });
            exit(1);
        }
        MRRegister(dispatch_get_main_queue());
        NSArray *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                dispatch_async(dispatch_get_main_queue(), ^{ scheduleRefresh(); });
            }];
        }
        emit(@{ @"type": @"ready" });
        scheduleRefresh();

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            char buffer[256];
            while (fgets(buffer, sizeof buffer, stdin)) {
                NSString *line = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                dispatch_async(dispatch_get_main_queue(), ^{ handleCommand(line); });
            }
            // stdin closed: Notchy quit or restarted the adapter.
            exit(0);
        });
        // Elapsed time drifts without notifications; resync periodically.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ scheduleRefresh(); });
        dispatch_resume(timer);
        CFRunLoopRun();
    }
}
