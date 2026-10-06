// Spotify's own start-up screen: after iOS's launch screen (plain since scripts/launch-screen.sh) the
// app puts up a LaunchViewController of its own with the green logo on the grey, until its root screen
// is ready. The logo is swapped for the app icon the person picked on Mod > App icon, in the same screen
// and the same place, so the start is no longer or emptier than Spotify's: the grey stays, Spotify's views
// go to alpha 0 (not hidden: views inside Spotify's stacks crash when hidden), and the icon is drawn in
// the middle. The icon is the 60 pt picture scripts/app-icons.sh puts in the IPA for the list; without one
// Spotify's logo stays.
#import "Core/SGCore.h"

static char kIconKey;

// The list's name for the icon in use (App/About/AppIcon.m): Spotify's own is no alternate.
static NSString *iconFile(void) {
    NSString *name = UIApplication.sharedApplication.alternateIconName;
    return [name hasPrefix:@"SGAppIcon"] ? [name substringFromIndex:@"SGAppIcon".length] : @"Spotify";
}

static UIImage *iconImage(void) {
    NSString *path = [NSBundle.mainBundle pathForResource:iconFile() ofType:@"png" inDirectory:@"SGAppIconPreviews"];
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    return image ? [UIImage imageWithCGImage:image.CGImage scale:3 orientation:UIImageOrientationUp] : nil;
}

static void swapLogo(UIViewController *page) {
    UIView *root = page.viewIfLoaded;
    if (!root) return;
    UIImageView *icon = objc_getAssociatedObject(page, &kIconKey);
    if (!icon) {
        UIImage *image = iconImage();
        if (!image) return;
        CGFloat side = 96;
        icon = [[UIImageView alloc] initWithImage:image];
        icon.frame = CGRectMake(0, 0, side, side);
        icon.layer.cornerRadius = side * 0.225;
        icon.layer.cornerCurve = kCACornerCurveContinuous;
        icon.layer.masksToBounds = YES;
        icon.userInteractionEnabled = NO;
        objc_setAssociatedObject(page, &kIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    __block NSUInteger count = 0;
    SGForEachView(root, ^(UIView *v) {
        if (v == root || v == icon || v.alpha == 0) return;
        v.alpha = 0;
        count++;
    });
    if (icon.superview != root) [root addSubview:icon];
    icon.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
    [root bringSubviewToFront:icon];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"launch: Spotify's start-up logo swapped for the %@ icon (%lu views)", iconFile(), (unsigned long)count); });
}

%hook _TtC30ContainerUI_RootUIInternalImpl20LaunchViewController
- (void)viewDidLayoutSubviews {
    %orig;
    swapLogo((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    swapLogo((UIViewController *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC30ContainerUI_RootUIInternalImpl20LaunchViewController"]);
}
