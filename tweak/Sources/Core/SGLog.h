#import <Foundation/Foundation.h>
#import <os/log.h>

// %{public}s so idevicesyslog on the Mac sees the text instead of <private>. Every line also goes to
// Documents/Sigma/log.txt in Spotify's container (SGLogToFile), which the Files app shows, so a log can be
// read without a Mac.
void SGLogToFile(NSString *line);
#define SGLog(fmt, ...) do { NSString *sg_line = [NSString stringWithFormat:(fmt), ##__VA_ARGS__];     os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[spotifyglass] %{public}s", sg_line.UTF8String);     SGLogToFile(sg_line); } while (0)

// Long dumps, split into numbered parts under the unified log's size cap.
void SGLogLong(NSString *tag, NSString *text);
// Logs every class of the list that this Spotify does not have; a feature calls it from its %ctor.
void SGRequireClasses(NSArray<NSString *> *names);
