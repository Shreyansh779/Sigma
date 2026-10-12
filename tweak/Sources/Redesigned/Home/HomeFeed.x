// Home redesign: the shelves switched off never reach Home. Spotify's feed (GET /casita/v1/home/..., a
// spotify.casita.v1.resolved.ResolvedHome protobuf) names every section in its first field: one entry each with the
// section's id ("spotify:section:...|new-releases-carousel") and a heading with the shelf's title, plain ("Recents")
// or with a template over a name ("For fans of {0}" over "Metro Boomin", which the view knows as "For fans of ...").
// A shelf switched off is cut out of that list as the response arrives, so the page never makes a cell for it, never
// sizes it, and leaves no gap or jump. Everything else in the body goes through byte for byte, and any body that does
// not parse as expected goes through whole. HomeSections.x still drops what a section of the feed was not cut.
//
// The body is held until the request ends and then handed to Spotify's delegate in one piece, as the lyrics page does
// (Shared/LyricsSources/LyricsHook.x). Only while a shelf is switched off (SGRHomeShelfFilterActive).
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Home.h"

typedef void (^SGRFeedDisposition)(NSURLSessionResponseDisposition disposition);

@interface SGRFeedState : NSObject
@property (nonatomic, strong) NSMutableData *body;
@property (nonatomic, strong) NSData *handing;   // the body this file is giving Spotify's delegate
@end
@implementation SGRFeedState
@end

static char kFeedKey;
static const NSUInteger kMaxBody = 8 * 1024 * 1024;

#pragma mark - protobuf

static BOOL readVarint(const uint8_t *b, NSUInteger *i, NSUInteger hi, uint64_t *out) {
    uint64_t value = 0;
    for (int shift = 0; shift < 64 && *i < hi; shift += 7) {
        uint8_t c = b[(*i)++];
        value |= (uint64_t)(c & 0x7F) << shift;
        if (!(c & 0x80)) {
            *out = value;
            return YES;
        }
    }
    return NO;
}

// Each field of the message in [lo, hi): its number, wire type, where it starts, where its payload is and where it ends.
// The block answers NO to stop. The result is NO when the bytes are not a message.
typedef BOOL (^SGRFieldBlock)(uint32_t field, int wire, NSUInteger start, NSUInteger payloadLo, NSUInteger payloadHi, NSUInteger end);

static BOOL eachField(const uint8_t *b, NSUInteger lo, NSUInteger hi, SGRFieldBlock fn) {
    NSUInteger i = lo;
    while (i < hi) {
        NSUInteger start = i;
        uint64_t key = 0, length = 0;
        if (!readVarint(b, &i, hi, &key)) return NO;
        uint32_t field = (uint32_t)(key >> 3);
        int wire = (int)(key & 7);
        NSUInteger payloadLo = i, payloadHi = i;
        if (wire == 0) {
            uint64_t ignored;
            if (!readVarint(b, &i, hi, &ignored)) return NO;
            payloadHi = i;
        } else if (wire == 1) {
            if (i + 8 > hi) return NO;
            i += 8;
            payloadHi = i;
        } else if (wire == 5) {
            if (i + 4 > hi) return NO;
            i += 4;
            payloadHi = i;
        } else if (wire == 2) {
            if (!readVarint(b, &i, hi, &length) || length > hi - i) return NO;
            payloadLo = i;
            i += (NSUInteger)length;
            payloadHi = i;
        } else {
            return NO;
        }
        if (!fn(field, wire, start, payloadLo, payloadHi, i)) return YES;
    }
    return YES;
}

static NSString *textAt(const uint8_t *b, NSUInteger lo, NSUInteger hi) {
    return hi > lo ? [[NSString alloc] initWithBytes:b + lo length:hi - lo encoding:NSUTF8StringEncoding] : nil;
}

// The first length-delimited field numbered `field` in the message [lo, hi), as a range; NO when there is none.
static BOOL firstBytes(const uint8_t *b, NSUInteger lo, NSUInteger hi, uint32_t field, NSUInteger *outLo, NSUInteger *outHi) {
    __block BOOL found = NO;
    eachField(b, lo, hi, ^BOOL(uint32_t f, int wire, NSUInteger start, NSUInteger pl, NSUInteger ph, NSUInteger end) {
        if (f != field || wire != 2) return YES;
        *outLo = pl;
        *outHi = ph;
        found = YES;
        return NO;
    });
    return found;
}

// The identity of a shelf as the view gives it: its title, or a template's text before "{0}" and an ellipsis.
static NSString *sectionIdentity(const uint8_t *b, NSUInteger lo, NSUInteger hi) {
    __block NSString *identity = nil;
    eachField(b, lo, hi, ^BOOL(uint32_t field, int wire, NSUInteger start, NSUInteger pl, NSUInteger ph, NSUInteger end) {
        if (field == 1 || wire != 2) return YES;
        NSUInteger hl, hh, tl, th;
        // The shelf's own field (3, 4, 6, 10, 25...): the heading (1), plain (2) or templated (3), the text its first field.
        if (!firstBytes(b, pl, ph, 1, &hl, &hh)) return YES;
        if (firstBytes(b, hl, hh, 2, &tl, &th) && firstBytes(b, tl, th, 1, &tl, &th)) {
            identity = textAt(b, tl, th);
        } else if (firstBytes(b, hl, hh, 3, &tl, &th) && firstBytes(b, tl, th, 1, &tl, &th)) {
            NSString *template = textAt(b, tl, th);
            NSRange marker = [template rangeOfString:@"{0}"];
            if (template && marker.location != NSNotFound) {
                NSString *lead = [[template stringByReplacingCharactersInRange:marker withString:@""]
                                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                identity = [lead stringByAppendingString:@" …"];
            }
        }
        return !identity;
    });
    return [identity stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static void appendVarint(NSMutableData *out, uint64_t value) {
    do {
        uint8_t c = value & 0x7F;
        value >>= 7;
        if (value) c |= 0x80;
        [out appendBytes:&c length:1];
    } while (value);
}

// The feed without the sections switched off, or nil when nothing was cut or the bytes are not as expected.
static NSData *withoutHiddenShelves(NSData *body) {
    const uint8_t *b = body.bytes;
    NSUInteger length = body.length;
    __block NSUInteger structureLo = 0, structureHi = 0, structureStart = 0, structureEnd = 0;
    __block BOOL found = NO;
    BOOL ok = eachField(b, 0, length, ^BOOL(uint32_t field, int wire, NSUInteger start, NSUInteger pl, NSUInteger ph, NSUInteger end) {
        if (field != 1 || wire != 2) return YES;
        structureStart = start;
        structureLo = pl;
        structureHi = ph;
        structureEnd = end;
        found = YES;
        return NO;
    });
    if (!ok || !found) return nil;

    NSMutableData *kept = [NSMutableData data];
    NSMutableArray<NSString *> *cut = [NSMutableArray array];
    __block NSUInteger sections = 0;
    ok = eachField(b, structureLo, structureHi, ^BOOL(uint32_t field, int wire, NSUInteger start, NSUInteger pl, NSUInteger ph, NSUInteger end) {
        if (field == 1 && wire == 2) {
            sections++;
            NSString *identity = sectionIdentity(b, pl, ph);
            if (identity.length && SGRHomeShelfHidden(identity)) {
                [cut addObject:identity];
                return YES;
            }
        }
        [kept appendBytes:b + start length:end - start];
        return YES;
    });
    if (!ok || !cut.count) return nil;

    NSMutableData *out = [NSMutableData dataWithCapacity:length];
    [out appendBytes:b length:structureStart];
    uint8_t tag = 0x0A;
    [out appendBytes:&tag length:1];
    appendVarint(out, kept.length);
    [out appendData:kept];
    [out appendBytes:b + structureEnd length:length - structureEnd];
    SGLog(@"redesign home feed: %lu sections, %lu cut: %@", (unsigned long)sections, (unsigned long)cut.count, [cut componentsJoinedByString:@", "]);
    return out;
}

#pragma mark - the request

static SGRFeedState *stateOf(NSURLSessionTask *task) {
    id state = objc_getAssociatedObject(task, &kFeedKey);
    return [state isKindOfClass:SGRFeedState.class] ? state : nil;
}

static void startFeed(NSURLSessionTask *task, NSURLResponse *response) {
    if (stateOf(task) || !SGRHomeShelfFilterActive()) return;
    NSURL *url = task.currentRequest.URL ?: task.originalRequest.URL;
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    if (!http || http.statusCode != 200 || ![url.path hasPrefix:@"/casita/v1/home/"]) return;
    SGRFeedState *state = [SGRFeedState new];
    state.body = [NSMutableData data];
    objc_setAssociatedObject(task, &kFeedKey, state, OBJC_ASSOCIATION_RETAIN);
}

// YES when the bytes go on to Spotify's delegate: not the feed's, which are held, nor any but what this file hands over.
static BOOL forwardsData(NSURLSessionTask *task, NSData *data) {
    SGRFeedState *state = stateOf(task);
    if (!state) return YES;
    @synchronized (state) {
        if (data == state.handing) return YES;
        if (state.body && state.body.length + data.length <= kMaxBody) [state.body appendData:data];
        else state.body = nil;   // too large to be the feed
        return NO;
    }
}

static NSData *takeBody(NSURLSessionTask *task) {
    SGRFeedState *state = stateOf(task);
    if (!state) return nil;
    @synchronized (state) {
        NSData *body = state.body;
        state.body = nil;
        return body;
    }
}

static void give(id delegate, NSURLSession *session, NSURLSessionDataTask *task, NSData *body) {
    SGRFeedState *state = stateOf(task);
    if (!body.length || !state) return;
    @synchronized (state) { state.handing = body; }
    [delegate URLSession:session dataTask:task didReceiveData:body];
    @synchronized (state) { state.handing = nil; }
}

static void finished(id delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    if (!stateOf(task)) return;
    NSData *body = takeBody(task);
    if (error || !body.length) return;
    NSData *cut = withoutHiddenShelves(body);
    give(delegate, session, (NSURLSessionDataTask *)task, cut ?: body);
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGRFeedDisposition)handler {
    startFeed(task, response);
    %orig;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (forwardsData(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    finished(self, session, task, error);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGRFeedDisposition)handler {
    startFeed(task, response);
    %orig;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (forwardsData(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    finished(self, session, task, error);
    %orig;
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGRHomeShelfFilterActive()) return;
    %init;
}
