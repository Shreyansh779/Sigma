#import "SGLog.h"
#import "SGPrefs.h"

// Kept short: a log past this size is moved to log.old.txt (replacing the one before) and started again at the
// next launch, so a crash right after the switch still has the run-up to it.
static const unsigned long long kLogLimit = 5 * 1024 * 1024;

BOOL SGDebugLog(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGKeyDebugLog); });
    return on;
}

void SGLogToFile(NSString *line) {
    if (!SGDebugLog()) return;
    static dispatch_queue_t queue;
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("sigma.log", DISPATCH_QUEUE_SERIAL);
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *folder = [documents stringByAppendingPathComponent:@"Sigma"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        path = [folder stringByAppendingPathComponent:@"log.txt"];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if (attributes.fileSize > kLogLimit) {
            NSString *old = [folder stringByAppendingPathComponent:@"log.old.txt"];
            [NSFileManager.defaultManager removeItemAtPath:old error:nil];
            [NSFileManager.defaultManager moveItemAtPath:path toPath:old error:nil];
        }
        NSString *mark = [NSString stringWithFormat:@"---- launch %@ ----\n", NSDate.date];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[mark dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } else {
            [mark writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    });
    NSString *stamped = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, line];
    dispatch_async(queue, ^{
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) return;
        [handle seekToEndOfFile];
        [handle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    });
}

// The unified log cuts a message at about 1 KB, so long dumps go out as numbered parts.
void SGLogLong(NSString *tag, NSString *text) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (current.length && [current lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 900) {
            [parts addObject:[current copy]];
            [current setString:@""];
        }
        [current appendFormat:@"%@\n", line];
    }
    if (current.length) [parts addObject:current];
    [parts enumerateObjectsUsingBlock:^(NSString *part, NSUInteger i, BOOL *stop) {
        NSString *line = [NSString stringWithFormat:@"%@ %lu/%lu\n%@", tag, (unsigned long)i + 1, (unsigned long)parts.count, part];
        // Only the hang samples go to the file log: the other dumps run to megabytes and would swamp it.
        if ([tag hasPrefix:@"hang"]) SGLogToFile(line);
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[spotifyglass] %{public}s", line.UTF8String);
    }];
}

void SGRequireClasses(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!NSClassFromString(name)) SGLog(@"class %@ not found, its hooks are inactive", name);
    }
}
