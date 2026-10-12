// What Spotify's web requests carry while Home loads, to find the feed's request and see its body: for each distinct
// request path the first response's status, type and encoding; for a response whose path has "casita" in it (Home's
// feed, a spotify.casita.v1.resolved.ResolvedHome protobuf) its size, its first bytes and the strings in its first 4 KB,
// and the first three bodies written whole to Documents/Sigma/casita-N.bin. Observes only: every call goes on as it was.
// Debug log only.
#import "Core/SGCore.h"

typedef void (^SGFeedDisposition)(NSURLSessionResponseDisposition disposition);

static NSMapTable<NSURLSessionTask *, NSMutableData *> *sg_bodies;
static NSMutableSet<NSString *> *sg_paths;
static NSUInteger sg_saved;
static const NSUInteger kMaxPaths = 150, kMaxBody = 4 * 1024 * 1024, kMaxSaved = 3;

static id FeedTraceLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL isFeed(NSURL *url) {
    return [url.absoluteString.lowercaseString containsString:@"casita"];
}

static NSString *hex(NSData *data, NSUInteger count) {
    NSMutableString *out = [NSMutableString string];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < MIN(count, data.length); i++) [out appendFormat:@"%02x", bytes[i]];
    return out;
}

static void noteResponse(NSURLSessionTask *task, NSURLResponse *response) {
    NSURL *url = response.URL ?: task.originalRequest.URL;
    if (!url) return;
    NSString *key = [NSString stringWithFormat:@"%@%@", url.host ?: @"", url.path ?: @""];
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    @synchronized (FeedTraceLock()) {
        if (!sg_paths) sg_paths = [NSMutableSet set];
        if (![sg_paths containsObject:key] && sg_paths.count < kMaxPaths) {
            [sg_paths addObject:key];
            SGLog(@"feed: %@ %@ status %ld type %@ encoding %@ length %lld", task.originalRequest.HTTPMethod ?: @"GET", key,
                  (long)http.statusCode, response.MIMEType, http.allHeaderFields[@"Content-Encoding"], response.expectedContentLength);
        }
        if (isFeed(url)) {
            if (!sg_bodies) sg_bodies = [NSMapTable weakToStrongObjectsMapTable];
            [sg_bodies setObject:[NSMutableData data] forKey:task];
            SGLog(@"feed: casita response %@ headers %@", url.absoluteString, http.allHeaderFields);
        }
    }
}

static void noteData(NSURLSessionTask *task, NSData *data) {
    @synchronized (FeedTraceLock()) {
        NSMutableData *body = [sg_bodies objectForKey:task];
        if (body && body.length < kMaxBody) [body appendData:data];
    }
}

static void noteDone(NSURLSessionTask *task) {
    NSMutableData *body;
    @synchronized (FeedTraceLock()) {
        body = [sg_bodies objectForKey:task];
        if (body) [sg_bodies removeObjectForKey:task];
    }
    if (!body) return;
    NSData *head = [body subdataWithRange:NSMakeRange(0, MIN(body.length, 4096))];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSMutableString *run = [NSMutableString string];
    const unsigned char *bytes = head.bytes;
    for (NSUInteger i = 0; i <= head.length && strings.count < 24; i++) {
        BOOL printable = i < head.length && bytes[i] >= 0x20 && bytes[i] < 0x7F;
        if (printable) [run appendFormat:@"%c", bytes[i]];
        else {
            if (run.length >= 6) [strings addObject:[run copy]];
            [run setString:@""];
        }
    }
    SGLog(@"feed: casita body %lu bytes, gzip %@, first bytes %@, strings %@", (unsigned long)body.length,
          body.length > 1 && bytes[0] == 0x1f && bytes[1] == 0x8b ? @"yes" : @"no", hex(body, 96), strings);
    if (sg_saved < kMaxSaved) {
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Sigma"];
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"casita-%lu.bin", (unsigned long)++sg_saved]];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [body writeToFile:path atomically:YES];
        SGLog(@"feed: casita body written to %@", path);
    }
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGFeedDisposition)handler {
    noteResponse(task, response);
    %orig;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    noteData(task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    noteDone(task);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGFeedDisposition)handler {
    noteResponse(task, response);
    %orig;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    noteData(task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    noteDone(task);
    %orig;
}
%end

%ctor {
    if (!SGDebugLog()) return;
    %init;
}
