// Spotify's own start-up screen: after iOS's launch screen (plain since scripts/launch-screen.sh) the
// app puts up a LaunchViewController of its own with the green logo on the grey, until its root screen
// is ready. The logo goes, so the start stays the plain dark screen it began as; the grey behind it stays.
// Alpha, not hidden: views inside Spotify's stacks crash when hidden (AGENTS.md).
#import "Core/SGCore.h"

static void blank(UIViewController *page) {
    UIView *root = page.viewIfLoaded;
    if (!root) return;
    __block NSUInteger count = 0;
    SGForEachView(root, ^(UIView *v) {
        if (v == root || v.alpha == 0) return;
        v.alpha = 0;
        count++;
    });
    static dispatch_once_t once;
    if (count) dispatch_once(&once, ^{ SGLog(@"launch: Spotify's own start-up screen blanked (%lu views)", (unsigned long)count); });
}

%hook _TtC30ContainerUI_RootUIInternalImpl20LaunchViewController
- (void)viewDidLayoutSubviews {
    %orig;
    blank((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    blank((UIViewController *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC30ContainerUI_RootUIInternalImpl20LaunchViewController"]);
}
