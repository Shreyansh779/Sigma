// Marks the native album header's ⋯ the moment it is tapped, so Shared/AlbumQueue knows which album the
// context menu sheet that follows is for. Both UIKit dispatch paths are watched, the way
// Shared/Haptics/ControlHaptics.x watches a control: target/selector and UIAction.
#import "Core/SGCore.h"
#import "Shared/AlbumQueue/AlbumQueue.h"

static NSString *const kPageClass = @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView";
// The album header that carries the ⋯, the same id Redesigned/Album/AlbumHeader.x finds it in.
static NSString *const kHeaderID = @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader";
static const UIControlEvents kActivationEvents = UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered;

static BOOL isMenuButton(UIControl *control) {
    return [control.accessibilityIdentifier hasPrefix:SGAlbumQueueButtonPrefix];
}

// The album `view`'s ⋯ is for, or nil. The page model is the authority on which album (and that it is an
// album, not an episode on the same template); the ⋯ must carry that album's id and sit in the header, so a
// track row's ⋯ on the same page is left alone.
static NSString *albumForButton(UIControl *view) {
    static Class pageClass;
    if (!pageClass) pageClass = NSClassFromString(kPageClass);
    UIView *page = view;
    while (page && ![page isKindOfClass:pageClass]) page = page.superview;
    if (!page) return nil;
    NSString *uri = SGAlbumQueueAlbumForPage(page);
    if (!uri) return nil;
    NSString *identifier = [SGAlbumQueueButtonPrefix stringByAppendingString:[uri substringFromIndex:@"spotify:album:".length]];
    if (![view.accessibilityIdentifier isEqualToString:identifier]) return nil;
    for (UIView *v = view; v && v != page; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kHeaderID]) return uri;
    }
    // A pinned ⋯ lives outside the header; accept it only when the original of the same id is in the header.
    __block BOOL matches = NO;
    SGForEachView(page, ^(UIView *header) {
        if (![header.accessibilityIdentifier isEqualToString:kHeaderID]) return;
        SGForEachView(header, ^(UIView *v) { if ([v.accessibilityIdentifier isEqualToString:identifier]) matches = YES; });
    });
    return matches ? uri : nil;
}

static void markFrom(UIControl *control) {
    NSString *uri = albumForButton(control);
    if (uri) SGAlbumQueueMarkAlbum(uri);
}

%hook UIControl
- (void)sendAction:(SEL)selector to:(id)target forEvent:(UIEvent *)event {
    if (isMenuButton(self)) {
        __block BOOL activates = NO;
        [self enumerateEventHandlers:^(UIAction *action, id registeredTarget, SEL registeredSelector, UIControlEvents events, BOOL *stop) {
            if (!action && registeredSelector == selector && (!registeredTarget || registeredTarget == target) && (events & kActivationEvents)) activates = YES;
        }];
        if (activates) markFrom(self);
    }
    %orig;
}
- (void)sendAction:(UIAction *)action {
    if (isMenuButton(self)) {
        __block BOOL activates = NO;
        [self enumerateEventHandlers:^(UIAction *registered, id target, SEL selector, UIControlEvents events, BOOL *stop) {
            if (registered == action && (events & kActivationEvents)) activates = YES;
        }];
        if (activates) markFrom(self);
    }
    %orig;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
}
