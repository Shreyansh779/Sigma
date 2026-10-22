// NowPlayingExtras.h says what this is and why it stores nothing of Spotify's.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Shared/Player/NowPlayingExtras.h"

// Read on whatever thread Spotify sets the info from, written on the main one.
static NSObject *sg_lock;
static NSMutableDictionary<NSString *, NSDictionary *> *sg_extras;   // by owner
static NSMutableDictionary<NSString *, NSString *> *sg_titles;       // by owner
static double sg_elapsed, sg_rate;
static CFAbsoluteTime sg_clockAt;
static NSString *sg_lastMiss;   // the last incoming title logged as dropping an owner, so a stream is one line

// `stale` are an owner's old keys: the info the getter gives back can still carry them, and the hook puts
// back only the extras that are current.
static void resend(NSArray *stale) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy];
    if (!info) return;
    [info removeObjectsForKeys:stale];
    @synchronized (sg_lock) {
        if (sg_clockAt > 0) info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(sg_elapsed + sg_rate * (CFAbsoluteTimeGetCurrent() - sg_clockAt));
    }
    center.nowPlayingInfo = info;
}

void SGNowPlayingSetExtras(NSString *owner, NSDictionary *extras, NSString *title) {
    NSDictionary *old;
    @synchronized (sg_lock) {
        old = sg_extras[owner];
        sg_extras[owner] = extras.count ? extras : nil;
        sg_titles[owner] = extras.count ? title : nil;
    }
    if (extras.count) {
        resend(old.allKeys ?: @[]);
        return;
    }
    // Cleared, they are taken off if they are still on: the next track can have the same title, and then
    // the last track's artwork or ISRC rode on its info.
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    for (id key in old) {
        if (![info[key] isEqual:old[key]]) continue;
        resend(old.allKeys);
        return;
    }
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    NSMutableDictionary *added = nil;
    NSString *missOwner = nil, *missStored = nil, *missIncoming = nil;   // a pending owner this update drops
    @synchronized (sg_lock) {
        if (info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
            sg_elapsed = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
            // A rate left out runs at 1, as LockScreenLyrics.x reads it.
            NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
            sg_rate = rate ? rate.doubleValue : 1;
            sg_clockAt = CFAbsoluteTimeGetCurrent();
        }
        id title = info[MPMediaItemPropertyTitle];
        for (NSString *owner in sg_extras) {
            if (![title isEqual:sg_titles[owner]]) {
                missOwner = owner; missStored = sg_titles[owner]; missIncoming = title;
                continue;
            }
            if (!added) added = [NSMutableDictionary dictionary];
            [added addEntriesFromDictionary:sg_extras[owner]];
        }
        // Diagnostic: this update's title matches no pending owner, so that owner's extras ride no further.
        // Suppressed once logged for a title, so position updates for the same mismatch stay one line.
        if (missStored) {
            NSString *mark = missIncoming ?: @"";
            if ([mark isEqual:sg_lastMiss]) missStored = nil;
            else sg_lastMiss = mark;
        }
    }
    if (missStored)
        SGLog(@"lock motion: now playing titled %@ matches no pending %@ (\"%@\"), its extras drop",
              missIncoming ? [NSString stringWithFormat:@"\"%@\"", missIncoming] : @"(none)", missOwner, missStored);
    if (!added) {
        %orig;
        return;
    }
    NSMutableDictionary *withExtras = [info mutableCopy];
    [withExtras addEntriesFromDictionary:added];
    %orig(withExtras);
}
%end

%ctor {
    sg_lock = [NSObject new];
    sg_extras = [NSMutableDictionary dictionary];
    sg_titles = [NSMutableDictionary dictionary];
    %init;
}
