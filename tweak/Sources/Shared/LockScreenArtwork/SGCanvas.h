// A clip to play as the lock screen's artwork, as plain data: where it is and what to call it on disk.
#import <Foundation/Foundation.h>

@interface SGCanvas : NSObject
@property (nonatomic, copy) NSString *identifier;   // names the file on disk
@property (nonatomic, copy) NSString *address;      // the clip's URL
@property (nonatomic) BOOL video;                   // an IMAGE or GIF canvas is not one of ours
@end
