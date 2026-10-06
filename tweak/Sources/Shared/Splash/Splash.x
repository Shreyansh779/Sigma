// The app icon in use, shown while Spotify starts. iOS draws the launch screen before any code runs and
// it is one picture for every icon, so the build leaves it plain (scripts/launch-screen.sh) and the icon
// the person picked on Mod > App icon comes up over Spotify's own start-up instead, until Home appears
// or a few seconds have gone. The picture is the 60 pt one scripts/app-icons.sh puts in the IPA for the list.
#import "Core/SGCore.h"

// Longest the icon stays up when Home never comes: a login screen, a failed start.
static const NSTimeInterval kLongest = 4;
static const NSUInteger kSceneTries = 60;

static UIWindow *sg_splash;
static BOOL sg_gone;

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

static void dismiss(void) {
    if (sg_gone) return;
    sg_gone = YES;
    UIWindow *window = sg_splash;
    [UIView animateWithDuration:0.25 animations:^{ window.alpha = 0; } completion:^(BOOL finished) {
        window.hidden = YES;
        sg_splash = nil;
    }];
}

static void show(NSUInteger tries) {
    if (sg_gone || sg_splash) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
    }
    if (!scene) {
        if (tries) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ show(tries - 1); });
        return;
    }
    UIImage *image = iconImage();
    if (!image) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 100;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *page = [UIViewController new];
    // Spotify's own launch screen grey.
    page.view.backgroundColor = [UIColor colorWithWhite:0x12 / 255.0 alpha:1];
    CGFloat side = 96;
    UIImageView *icon = [[UIImageView alloc] initWithImage:image];
    icon.frame = CGRectMake(0, 0, side, side);
    icon.center = CGPointMake(CGRectGetMidX(page.view.bounds), CGRectGetMidY(page.view.bounds));
    icon.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin
        | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    icon.layer.cornerRadius = side * 0.225;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.layer.masksToBounds = YES;
    [page.view addSubview:icon];
    window.rootViewController = page;
    window.hidden = NO;
    sg_splash = window;
    SGLog(@"splash: %@ icon up", iconFile());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLongest * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ dismiss(); });
}

// Home has drawn: the icon goes.
%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ dismiss(); });
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC19Home_FunkisPageImpl20FunkisViewController"]);
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) { show(kSceneTries); }];
}
