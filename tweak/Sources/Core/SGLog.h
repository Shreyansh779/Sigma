#import <Foundation/Foundation.h>
#import <os/log.h>

// %{public}s so idevicesyslog on the Mac sees the text instead of <private>. With Debug log on (below)
// every line also goes to Documents/Sigma/log.txt in Spotify's container (SGLogToFile), which the Files app
// shows, so a log can be read without a Mac.
void SGLogToFile(NSString *line);
// Mod > Mod > Debug log, read at launch: the file log above, the touch trace (Diagnostics/TouchTrace.x) and the
// stall sampler on the player's ⋯ are all off unless it is on, since they record what the person does.
#define SGKeyDebugLog @"spotifyglass.debugLog"
BOOL SGDebugLog(void);
// The current file log's text (Documents/Sigma/log.txt), for the Device logs page; a message when it is empty
// or unreadable. Reads the file directly, so it is fine to call off the log queue.
NSString *SGLogContents(void);
#define SGLog(fmt, ...) do { NSString *sg_line = [NSString stringWithFormat:(fmt), ##__VA_ARGS__];     os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[spotifyglass] %{public}s", sg_line.UTF8String);     SGLogToFile(sg_line); } while (0)

// Long dumps, split into numbered parts under the unified log's size cap.
void SGLogLong(NSString *tag, NSString *text);
// Logs every class of the list that this Spotify does not have; a feature calls it from its %ctor.
void SGRequireClasses(NSArray<NSString *> *names);
