// The lock screen's artwork moves: the track's Canvas, else Apple Music's animated album cover, and with
// Every song chosen, failing both, the cover over a moving blur of itself (SGFluidClip.h). iOS 26 takes a
// local video through MPMediaItemAnimatedArtwork under one of two now playing keys, 1:1 or 3:4, of those
// the system lists. It rides on Spotify's now playing info as an extra (Shared/Player/NowPlayingExtras.h).
//
// The clip itself is fetched and cut Sigma's way (Shared/LockScreenArtwork/), Vitrine's follower deciding when.
//
// The system turns down a clip of another shape than its key's, and a preview still of another shape with
// it, so a clip that does not fit (a Canvas is mostly 9:16) is letterboxed into the key's shape on black bars
// (SGArtworkCrop), end to end rather than cut about its middle, and the still, taken from that fitted clip,
// is the same shape as the video. The fitted clip, like the cover's clip, is made only when the lock screen
// asks for the video, and kept: it by the clip and shape, the cover's clip by the picture the track names, so
// an album's songs share one.
//
// The choice is read on every track, and a change applies at once: Off takes the clip away, Moving artwork
// and Every song look the playing track up. Lyrics is LyricsArtwork.x's, which reads it the same way, so the
// lock screen widget's star (Shared/LockScreenLyrics/LockScreenStar.x) can swap the two without a restart.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"
#import "SGFluidClip.h"
#import "SGMotionClip.h"
#import "Shared/LockScreenArtwork/SGAppleArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"

// How far a clip's width over height may be from its key's and still be taken as it is.
static const CGFloat kSameShape = 0.02;

static NSString *sg_title;
static NSString *sg_picture;   // the picture the track names, for the cover's clip
static NSUInteger sg_walk;   // counts the tracks walked, so a poster that comes late is told from the newest
static SGLockArtwork sg_choice;
static dispatch_queue_t sg_queue;   // cuts clips and makes the cover's, one at a time
static SGMotionFollower *sg_follower;

static BOOL motionOn(SGLockArtwork choice) {
    return choice == SGLockArtworkMotion || choice == SGLockArtworkEverySong;
}

// The key a clip shown at `shown` goes under, and the shape it is cut to (width over height): 1:1 for a
// square clip, else 3:4, each where the system lists it, else the other. nil while it lists neither, before
// MediaPlayer has started: the next track asks again.
API_AVAILABLE(ios(26.0))
static NSString *keyFor(CGSize shown, CGFloat *ratio) {
    NSArray<NSString *> *keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys;
    BOOL square = shown.height > 0 && fabs(shown.width / shown.height - 1) <= kSameShape;
    BOOL tall = [keys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork];
    if ([keys containsObject:MPNowPlayingInfoProperty1x1AnimatedArtwork] && (square || !tall)) {
        *ratio = 1;
        return MPNowPlayingInfoProperty1x1AnimatedArtwork;
    }
    *ratio = 0.75;
    return tall ? MPNowPlayingInfoProperty3x4AnimatedArtwork : nil;
}

// `image` filled into `size` about its middle, at scale 1 and opaque, as the preview the system asked for.
static UIImage *filled(UIImage *image, CGSize size) {
    size = CGSizeMake(round(size.width), round(size.height));
    if (!image || size.width < 1 || size.height < 1 || image.size.width <= 0 || image.size.height <= 0) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

// Diagnostic: two seconds after the artwork is set, whether the Now Playing info holds it. The system asks for the
// clip only when it means to show it, so this tells apart "not set" from "set, but never shown".
API_AVAILABLE(ios(26.0))
static void confirmInfo(NSString *identifier, NSString *key, NSString *name) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        id held = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[key];
        SGLog(@"lock motion: %@ in the now playing info: %@ (artwork %@, the system lists %@)", name,
              held ? NSStringFromClass([held class]) : @"none", identifier, MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
    });
}

API_AVAILABLE(ios(26.0))
static void show(NSURL *file) {
    NSUInteger walk = sg_walk;
    NSString *title = sg_title;
    SGMotionPoster(file, ^(UIImage *poster) {
        if (!poster || poster.size.height <= 0 || walk != sg_walk) return;
        CGFloat ratio;
        NSString *key = keyFor(poster.size, &ratio);
        if (!key) {
            SGLog(@"lock motion: the system lists no key yet (%@)", MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
            return;
        }
        // A clip of the key's shape goes as it is (the crop already cut it once, so it is not scaled again); one of
        // another shape is cut again, and scaled up (SGMotionClipOutput).
        CGSize cut = SGMotionClipCut(poster.size, ratio), written = SGMotionClipOutput(cut);
        BOOL fits = fabs(poster.size.width / poster.size.height - ratio) <= kSameShape;
        NSURL *shaped = fits ? file : SGMotionMadeFile([NSString stringWithFormat:@"cut\n%@\n%g\nv2", file.lastPathComponent, ratio]);
        if (!fits && !CGSizeEqualToSize(written, cut))
            SGLog(@"lock motion: %@ scaled up from %.0fx%.0f to %.0fx%.0f", file.lastPathComponent, cut.width, cut.height, written.width, written.height);
        MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:shaped.lastPathComponent
            previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
                SGLog(@"lock motion: %@ preview asked at %.0fx%.0f", shaped.lastPathComponent, wanted.width, wanted.height);
                completion(filled(poster, wanted));
            }
            videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
                SGLog(@"lock motion: %@ video asked at %.0fx%.0f", shaped.lastPathComponent, wanted.width, wanted.height);
                if (fits) {
                    completion(file);
                    return;
                }
                dispatch_async(sg_queue, ^{
                    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                    BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:shaped.path] || SGMotionClipShape(file, ratio, shaped);
                    SGLog(@"lock motion: %@ cut to %@ %@ in %.0f ms", file.lastPathComponent, ratio == 1 ? @"1:1" : @"3:4",
                          ok ? @"ready" : @"not written", (CFAbsoluteTimeGetCurrent() - start) * 1000);
                    completion(ok ? shaped : nil);
                });
            }];
        SGNowPlayingSetExtras(@"motion", @{key: artwork}, title);
        confirmInfo(shaped.lastPathComponent, key, @"motion");
        SGLog(@"lock motion: %@, %.0fx%.0f, as %@%@", file.lastPathComponent, written.width, written.height,
              ratio == 1 ? @"1:1" : @"3:4", fits ? @"" : @", cut to fit");
    });
}

// Sigma's own way to a clip (LockScreenArtwork/): the Canvas or Apple Music's cover downloaded under its own name
// and cut once to the key's shape (3:4 where the system lists it, else 1:1), so the file handed to the system fits
// as it is. The sources are asked in the order SGMotionSourceOrder keeps, the keys MotionSources.m gives them.
static NSString *const kCanvasSource = @"canvas";

// `done` on the main queue with the clip ready, or nil.
static void ready(NSString *identifier, NSString *address, CGFloat aspect, NSUInteger walk, void (^done)(NSURL *file)) {
    void (^finish)(NSURL *) = ^(NSURL *file) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (walk == sg_walk) done(file);
        });
    };
    SGArtworkFetch(identifier, address, ^(NSURL *file, NSString *note) {
        SGLog(@"lock motion: %@ %@", identifier, note);
        if (!file) {
            finish(nil);
            return;
        }
        SGArtworkCrop(file, identifier, aspect, ^(NSURL *cropped, NSString *cropNote) {
            SGLog(@"lock motion: %@ %@", identifier, cropNote);
            finish(cropped);
        });
    });
}

static void walkSources(NSArray<NSString *> *order, NSUInteger at, NSString *uri, NSURL *canvas, NSString *artist, NSString *album,
                        CGFloat aspect, NSUInteger walk, void (^done)(NSURL *file, NSString *source)) {
    if (at >= order.count) {
        done(nil, nil);
        return;
    }
    NSString *source = order[at];
    void (^next)(NSURL *) = ^(NSURL *file) {
        if (walk != sg_walk) return;
        if (file) done(file, source);
        else walkSources(order, at + 1, uri, canvas, artist, album, aspect, walk, done);
    };
    void (^fromCanvas)(NSURL *) = ^(NSURL *address) {
        if (walk != sg_walk) return;
        if (!address) {
            next(nil);
            return;
        }
        ready([address.lastPathComponent stringByDeletingPathExtension], address.absoluteString, aspect, walk, next);
    };
    if ([source isEqualToString:kCanvasSource]) {
        if (canvas) fromCanvas(canvas);
        else SGMotionCanvasFromService(uri, fromCanvas);
        return;
    }
    SGAppleArtworkFind(artist, album, aspect < 0.9, ^(SGCanvas *cover, NSString *note) {
        if (walk != sg_walk) return;
        SGLog(@"lock motion: Apple Music %@", cover ? @"has a cover" : note);
        if (cover.video) ready(cover.identifier, cover.address, aspect, walk, next);
        else next(nil);
    });
}

API_AVAILABLE(ios(26.0))
static void sigmaClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, void (^done)(NSURL *file, NSString *source)) {
    NSArray<NSString *> *keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys;
    BOOL tall = [keys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork];
    // Before MediaPlayer lists a key there is nothing to cut to: the next track asks again.
    if (!tall && ![keys containsObject:MPNowPlayingInfoProperty1x1AnimatedArtwork]) {
        done(nil, nil);
        return;
    }
    walkSources(SGMotionSourceOrder(), 0, uri, canvas, artist, album, tall ? 0.75 : 1, sg_walk, done);
}

// The cover Spotify handed the system for `title`, read on the main thread as LyricsArtwork.x reads it,
// then `then` on sg_queue with it, or with NULL when the info is another song's or has none.
static void withCover(NSString *title, void (^then)(CGImageRef cover)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
        MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
        UIImage *cover = [info[MPMediaItemPropertyTitle] isEqual:title] && [artwork isKindOfClass:MPMediaItemArtwork.class]
            ? [artwork imageWithSize:CGSizeMake(600, 600)] : nil;
        dispatch_async(sg_queue, ^{ then(cover.CGImage); });
    });
}

// The picture the track names, so the songs of an album share a clip; the track itself when it names none.
static NSString *pictureOf(SPTPlayerTrack *track, NSDictionary *metadata) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
        id value = metadata[field];
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return SGURIString(track.URI);
}

// The cover's clip is 3:4 (SGLyricsClipSize), so it goes only where the system lists that key.
API_AVAILABLE(ios(26.0))
static void showCover(NSString *picture) {
    if (![MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]) return;
    NSURL *file = SGMotionMadeFile([@"fluid\nv4\n" stringByAppendingString:picture]);
    NSString *title = sg_title;
    CGSize size = SGLyricsClipSize(SGMotionPixels());
    MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:file.lastPathComponent
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
            withCover(title, ^(CGImageRef cover) {
                CGImageRef frame = SGFluidClipFrame(cover, size);
                completion(frame ? filled([UIImage imageWithCGImage:frame], wanted) : nil);
                CGImageRelease(frame);
            });
        }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            withCover(title, ^(CGImageRef cover) {
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:file.path] || SGFluidClipWrite(file, cover, size);
                SGLog(@"lock motion: the cover's clip %@ %@ in %.0f ms", file.lastPathComponent, ok ? @"ready" : @"not written",
                      (CFAbsoluteTimeGetCurrent() - start) * 1000);
                completion(ok ? file : nil);
            });
        }];
    SGNowPlayingSetExtras(@"motion", @{MPNowPlayingInfoProperty3x4AnimatedArtwork: artwork}, title);
    confirmInfo(file.lastPathComponent, MPNowPlayingInfoProperty3x4AnimatedArtwork, @"cover");
    SGLog(@"lock motion: no moving artwork, the cover's clip offered as %@", file.lastPathComponent);
}

%ctor {
    if (@available(iOS 26.0, *)) {
        sg_choice = SGLockScreenArtwork();
        sg_queue = dispatch_queue_create("spotifyglass.lockscreen.motion", DISPATCH_QUEUE_SERIAL);
        // Each walk takes the last one's clip off first, so the lock screen falls back to the still cover.
        sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
            sg_walk++;
            SGArtworkCancelFetch();
            SGNowPlayingSetExtras(@"motion", nil, nil);
            NSDictionary *metadata = [state.track.metadata isKindOfClass:NSDictionary.class] ? state.track.metadata : nil;
            sg_title = state.track.trackTitle;
            sg_picture = pictureOf(state.track, metadata);
            sg_choice = SGLockScreenArtwork();
            return motionOn(sg_choice);
        } found:^(NSString *uri, NSURL *file) {
            if (file) show(file);
            else if (sg_choice == SGLockArtworkEverySong) showCover(sg_picture);
        }];
        sg_follower.clipFor = ^(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, void (^done)(NSURL *file, NSString *source)) {
            sigmaClip(uri, canvas, artist, album, done);
        };
        // Heard on the writing thread and handed to main without waiting: a main-queue observer makes every
        // background defaults write wait for main, which deadlocks launch while main waits on Spotify's CoreThread.
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLockArtwork choice = SGLockScreenArtwork();
                if (choice == sg_choice) return;
                SGLog(@"lock motion: the choice changed to %ld, the playing track looked up again", (long)choice);
                sg_choice = choice;
                [sg_follower restart];
            });
        }];
        SGLog(@"lock motion: %@, the lock screen takes %@", motionOn(sg_choice) ? (sg_choice == SGLockArtworkEverySong ? @"on for every song" : @"on") : @"off",
              MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
    }
}
