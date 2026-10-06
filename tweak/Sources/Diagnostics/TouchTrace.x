// Where each touch lands, for a tap that did nothing: when a finger goes down, the view that got it and the
// views above it, with the ones the mod made marked; and when it comes up, how long it was down and how far
// it moved. A tap that is missing from the log never reached the app; one on a view of the mod's was taken by
// an overlay; one on Spotify's button that did nothing is Spotify's. Only the first touches of a launch, so the
// file stays small, and nothing is logged while the finger moves.
#import "Core/SGCore.h"

static NSUInteger sg_traced;
static NSMapTable<UITouch *, NSNumber *> *sg_down;   // when each finger went down
static const NSUInteger kTraceLimit = 600;

static NSString *describe(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    BOOL ours = [name hasPrefix:@"SG"] || [name containsString:@"SGR"];
    NSString *identifier = view.accessibilityIdentifier;
    return [NSString stringWithFormat:@"%@%@%@", name, identifier.length ? [@" id=" stringByAppendingString:identifier] : @"", ours ? @" (mod)" : @""];
}

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches && sg_traced < kTraceLimit) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseBegan) {
                UIView *view = touch.view;
                NSMutableArray<NSString *> *chain = [NSMutableArray array];
                for (UIView *v = view; v && chain.count < 4; v = v.superview) [chain addObject:describe(v)];
                CGPoint at = [touch locationInView:nil];
                if (!sg_down) sg_down = [NSMapTable weakToStrongObjectsMapTable];
                [sg_down setObject:@(touch.timestamp) forKey:touch];
                sg_traced++;
                SGLog(@"touch: down at (%.0f, %.0f) on %@", at.x, at.y, [chain componentsJoinedByString:@" < "]);
            } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                NSNumber *was = [sg_down objectForKey:touch];
                if (!was) continue;
                [sg_down removeObjectForKey:touch];
                sg_traced++;
                SGLog(@"touch: %@ after %.2f s on %@", touch.phase == UITouchPhaseEnded ? @"up" : @"cancelled",
                      touch.timestamp - was.doubleValue, touch.view ? describe(touch.view) : @"nothing");
            }
        }
    }
    %orig;
}
%end

%ctor {
    if (!SGDebugLog()) return;
    %init;
}
