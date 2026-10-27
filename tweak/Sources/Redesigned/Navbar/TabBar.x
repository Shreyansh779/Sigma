// Tab bar: Spotify's own bar stays where it is but goes invisible, and a system UITabBar sits on top
// of it. On iOS 26+ with UIDesignRequiresCompatibility off, UIKit draws that bar as real Liquid Glass
// (selection bubble, lensing, light/dark adaptation) with no glass API of ours. Spotify's bar keeps
// its frame, so the page insets and the now playing bar stay where Spotify puts them; where the system
// bar is taller than Spotify's, Spotify is made to leave it the room (see "room for the glass bar").
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white, or the tab of the mod's own whose
// page is up (SGRNavbarLitTab), which Spotify does not know of. Navbar.x composes the
// hidden row, so its order, hidden tabs and tabs of the mod's own carry over. Always on in the redesign.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/TabIcons.h"
#import <objc/message.h>

static char kBarKey, kApartBarKey, kHostKey, kFadeKey, kDockKey;
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"
// Minimized, the bar gives way to two round glass buttons at its ends (the dock), the now playing card between
// them (SGRDockNowPlayingCard). See "the dock".
static BOOL sg_minimized;

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic) BOOL holding;
// The other bar, when the split tabs have one of their own: a tab picked on one bar clears the other's.
@property (nonatomic, weak) SGRSystemTabBar *partner;
// The item last shown selected, so a tap on it can be told from a tap that changes the tab.
@property (nonatomic, weak) UITabBarItem *shown;
@end

static void syncBar(UIView *stockBar);
static void layoutDockAndCard(UIView *stockBar);
static void applyMinimized(UIView *stockBar, BOOL animated);

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// An icon of the mod's own choosing, an Encore glyph or an SF Symbol, drawn off screen at the glyphs' size.
static UIImage *customGlyph(NSString *name, BOOL symbols) {
    if (!name.length) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%@", symbols ? @"symbols" : @"encore", name];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    UIView *custom = SGTabIconView(name, symbols, UIColor.whiteColor);
    CGSize size = CGSizeMake(24, 24);
    custom.translatesAutoresizingMaskIntoConstraints = YES;
    custom.frame = (CGRect){CGPointZero, size};
    [custom layoutIfNeeded];
    UIImage *image = renderLayer(custom.layer, size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

// A tab's canonical Encore glyph, built from the named SPTEncoreIcon rather than the live view, so the bar
// draws its own icon and not whichever one Spotify currently has on the item. Nil for a name Encore has not.
static UIImage *stockGlyph(NSString *name, BOOL active) {
    if (!name.length) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%d", name, active];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    SEL selector = NSSelectorFromString(name);
    if (!iconClass || !viewClass || ![iconClass respondsToSelector:selector]) return nil;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, selector);
    if (!icon) return nil;
    SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
    view.frame = CGRectMake(0, 0, 24, 24);
    [view setForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
    [view layoutIfNeeded];
    UIImage *image = renderLayer(view.layer, view.bounds.size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

// Apple Music's own tab, by the label Spotify's tab carries, for the Apple Music icons option.
static NSString *appleMusicSymbolForTab(NSString *title) {
    static NSDictionary<NSString *, NSString *> *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @{
            @"home": @"house.fill",
            @"listen now": @"house.fill",
            @"search": @"magnifyingglass",
            @"your library": @"square.stack.fill",
            @"library": @"square.stack.fill",
            @"browse": @"square.grid.2x2.fill",
            @"radio": @"dot.radiowaves.left.and.right",
        };
    });
    return symbols[title.lowercaseString];
}

// Encore draws a tab's icon from one SPTEncoreIcon in two states: isActive picks its filled variant.
// Both are drawn on an icon view of our own, off screen, so the images do not wait for Spotify's
// views to lay out and paint, and UITabBar swaps image and selectedImage itself.
//
// Spotify's own tabs draw a canonical icon of the bar's own: the one the entry names (a custom icon), an
// Apple Music SF Symbol when that option is on, or the tab's default Encore glyph. The mod's own tabs
// (SGRTabItemView) keep the icon their entry already draws, through the live path below.
static UIImage *glyphOf(UIView *item, BOOL active) {
    if (![NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) {
        NSString *title = labelIn(item).text;
        NSDictionary *stockEntry = nil;
        for (NSDictionary *entry in SGRNavbarLayout()) {
            if ([entry[SGRNavbarID] isEqualToString:title] && !entry[SGRNavbarURI]) {
                stockEntry = entry;
                NSString *name = entry[SGRNavbarIcon];
                if (SGRNavbarEntryHasCustomIcon(entry) && [name isKindOfClass:NSString.class])
                    return customGlyph(name, [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols]);
                break;
            }
        }
        if (SGFlag(SGRKeyNavbarAppleIcons, NO)) {
            NSString *symbol = appleMusicSymbolForTab(title);
            if (symbol) return customGlyph(symbol, YES);
        }
        UIImage *defaultIcon = stockGlyph(SGRNavbarDefaultIcon(stockEntry[SGRNavbarID] ?: title), active);
        if (defaultIcon) return defaultIcon;
    }

    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    return size.width >= 2 ? renderLayer(live.layer, size) : nil;
}

// For the Tab bar page's list and preview: a tab of Spotify's drawn from its item on the bar, hidden or not,
// found by the label its entry is named after; a tab of the mod's own drawn from its entry, as Navbar.x
// draws it on the bar. Nil while Spotify's item has not been built.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active) {
    if (entry[SGRNavbarURI]) {
        UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        UIView *icon = SGTabIconView(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], UIColor.whiteColor);
        icon.translatesAutoresizingMaskIntoConstraints = YES;
        icon.frame = holder.bounds;
        if ([icon isKindOfClass:UIImageView.class]) icon.contentMode = UIViewContentModeScaleAspectFit;
        [holder addSubview:icon];
        [holder layoutIfNeeded];
        return glyphOf(holder, active);
    }
    for (UIView *item in SGRowIn(sg_stockBar).arrangedSubviews) {
        if ([NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) continue;
        if ([labelIn(item).text isEqualToString:entry[SGRNavbarID]]) return glyphOf(item, active);
    }
    return nil;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

// For the now playing pill (NowPlayingBar.x): a tap on the docked card opens the player the way a tap on the bar does.
BOOL SGRFireTapRecognizers(UIView *view) {
    return fireTapRecognizers(view);
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

#pragma mark - the system bar

// A name too long for its tab (one of the user's own, a split tab's circle) shrinks a little before UIKit cuts
// it short, to 8 pt from 10.
void SGRShrinkTabTitles(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || ((UILabel *)v).adjustsFontSizeToFitWidth) return;
        ((UILabel *)v).adjustsFontSizeToFitWidth = YES;
        ((UILabel *)v).minimumScaleFactor = 0.8;
    });
}

@implementation SGRSystemTabBar

// UIKit makes the labels as it lays the items out, so they are shrunk after each pass.
- (void)layoutSubviews {
    [super layoutSubviews];
    SGRShrinkTabTitles(self);
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    BOOL again = item == self.shown;
    self.shown = item;
    // On the minimized bar the leading circle brings the whole bar back, as the Music app's does; passed on,
    // the tap would take Spotify's stack back to its root. Minimizing builds the circle's item anew, so it
    // is told by the bar it is on, not by being the item shown before.
    BOOL leading = self.stockBar && objc_getAssociatedObject(self.stockBar, &kBarKey) == self;
    if (sg_minimized && (again || leading)) {
        SGRSetTabBarMinimized(NO, YES);
        return;
    }
    // One of Spotify's own takes the light back from a tab of the mod's own.
    UIView *source = self.sources[index];
    if (![NSStringFromClass(source.class) isEqualToString:@"SGRTabItemView"]) SGRNavbarForgetTab();
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding) forwardTap(source);
    self.partner.selectedItem = nil;
    self.partner.shown = nil;
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

// UIKit's item views are private, so the item under a touch is the one whose title label or glyph is
// nearest. With the labels hidden only the glyph is left; UIKit shows the item's own image instance.
- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in self.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

// The system bar's own view in Spotify's bar. UIKit measures the system bar and lays it out by the safe
// area of the view it stands in, and the room made under Spotify's bar is not the phone's: on a phone
// with a home button it went under the platter as well, squeezing it to 49 pt. So this view hands the
// bar the safe area without the room.
@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}
@end

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - the fade under the bars

// The pages darken toward the bottom of the screen under the glass bar and the now playing bar, from clear
// a little above the now playing card to half black at the screen's foot, so a row going under the glass
// reads as passing behind it. Never darker than half: the glass still has the page to lens. The fade is the
// stock bar's own subview, behind the glass, so it slides away with the bar when a page hides it; Spotify's
// bar does not clip, or the glass bar would not have stood over the now playing bar before the room was made.
@interface SGRBarFade : UIView
@end

@implementation SGRBarFade
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

// The now playing card (56), its gap over the bar (8) and 24 more, whether a song is playing or not.
static const CGFloat kFadeAbove = 88;

static void placeFade(UIView *stockBar, CGRect glass) {
    SGRBarFade *fade = objc_getAssociatedObject(stockBar, &kFadeKey);
    if (!fade) {
        fade = [SGRBarFade new];
        fade.userInteractionEnabled = NO;
        CAGradientLayer *layer = (CAGradientLayer *)fade.layer;
        // Eased rather than straight, so the fade has no edge where it starts.
        layer.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.3].CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor];
        layer.locations = @[@0, @0.5, @1];
        objc_setAssociatedObject(stockBar, &kFadeKey, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    fade.hidden = !SGFlag(SGRKeyNavbarBottomGradient, YES);
    CGFloat top = CGRectGetMinY(glass) - kFadeAbove;
    CGRect frame = CGRectMake(0, top, stockBar.bounds.size.width, CGRectGetMaxY(glass) - top);
    if (!CGRectEqualToRect(fade.frame, frame)) fade.frame = frame;
    if (fade.superview != stockBar || stockBar.subviews.firstObject != fade) [stockBar insertSubview:fade atIndex:0];
}

// The Appearance page's Bottom navbar gradient switch: shows or hides the fade at once, without a restart.
void SGRSetTabBarGradientVisible(BOOL visible) {
    UIView *stockBar = sg_stockBar;
    SGRBarFade *fade = stockBar ? objc_getAssociatedObject(stockBar, &kFadeKey) : nil;
    fade.hidden = !visible;
    SGRRefreshTabBar();
}

#pragma mark - room for the glass bar

// UIKit's glass bar asks for 83 pt, the platter the top 62 of it, over no more safe area than a Face ID
// phone's 34 (simulator, iOS 26.5 and 27). Spotify's bar is its 49 pt row over the bottom safe area of
// TabBarContainerImpl's view: a guide from 49 pt above the safe area's bottom to the view's bottom sets
// its height (its viewDidLoad, 0x100840a2c), the now playing bar stands on that guide's top
// (MainUIContainer's chrome bottom anchor, 0x100ae0178), the bar slides away by the inset plus 49 when
// Spotify hides it (0x1037169a4) and the pages get 49 on top of the inset (0x10707bde4). A Face ID
// phone gives the view 34 and the two bars match. A phone with a home button gives it none, and so does
// Spotify's message bar (LimitedExperienceIndicatorBar: Offline, Private Session) coming in under the
// tab bar, which takes the home indicator's inset for itself: the glass bar stood 34 pt above
// Spotify's, over the now playing bar. So the view gets the rest of the glass bar's height as safe
// area, and Spotify lays its bar, the now playing bar, the pages and the hide out for the glass bar
// itself, and moves them all with the message bar.
static const CGFloat kStockRow = 49;

// UIKit asks for 62 + max(21, inset) on a phone with a home button, max(83, 49 + inset) on a Face ID
// phone, by the safe area of the view the bar stands in. SGRTabBarHost keeps the room out of that; if
// it ever reached the bar again, the bar would ask for more room every pass, so what it asks for with
// no room made is what is kept.
static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static SGRSystemTabBar *makeBar(UIView *stockBar) {
    SGRSystemTabBar *bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
    // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
    // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
    // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
    // the system is, and so is the bar.
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.delegate = bar;
    bar.stockBar = stockBar;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
    hold.delegate = bar;
    [bar addGestureRecognizer:hold];
    bar.hold = hold;
    return bar;
}

// One bar's share of the tabs: its items, their glyphs and titles. YES while a glyph is still missing.
static BOOL fillBar(SGRSystemTabBar *bar, NSArray<UIView *> *sources, BOOL hideLabels) {
    bar.tintColor = SGRAccent();
    if (![sources isEqualToArray:bar.sources]) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : labelIn(source).text image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        if (!item.image) item.image = glyphOf(sources[i], NO);
        if (!item.selectedImage || item.selectedImage == item.image) item.selectedImage = glyphOf(sources[i], YES);
        missing |= !item.image || !item.selectedImage;
        item.accessibilityLabel = labelIn(sources[i]).text;
        item.largeContentSizeImage = item.image;
        item.accessibilityHint = sg_minimized && bar == objc_getAssociatedObject(bar.stockBar, &kBarKey) ? @"Shows all tabs" : nil;
        NSString *title = hideLabels ? nil : labelIn(sources[i]).text;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
    }
    return missing;
}

// The bar holding the tab Spotify paints as selected selects it, and the other one lets go. With no tab
// painted (a tab of the mod's own, a repaint still to come) both keep what they have.
static void selectActive(SGRSystemTabBar *bar, UIView *active) {
    NSUInteger index = active ? [bar.sources indexOfObject:active] : NSNotFound;
    UITabBarItem *item = index == NSNotFound ? nil : bar.items[index];
    if (active && bar.selectedItem != item) bar.selectedItem = item;
    if (active && item) bar.shown = item;
}

// The tab a bar shows selected, when Spotify paints none: a tab of the mod's own.
static UIView *selectedSource(SGRSystemTabBar *bar) {
    NSUInteger index = bar.selectedItem ? [bar.items indexOfObject:bar.selectedItem] : NSNotFound;
    return index < bar.sources.count ? bar.sources[index] : nil;
}

// Split tabs stand on a glass bar of their own at the trailing end, the way the Music app sets Search
// apart. A standalone UITabBar has no way to set an item apart (iOS 27 SDK: only UITabBarController's
// UISearchTab does), so it is a second bar. UIKit draws each bar's platter 21 pt in from its sides
// (harness/tabbar, iPhone 17 Pro, iOS 27: a 72 pt bar got a 30 pt platter at x 21), so a split bar is
// a 62 pt platter, a circle as tall as the bar's, per tab plus those insets, and the main bar runs under
// its leading inset to leave 12 pt of glassless gap between the two platters.
static const CGFloat kPlatterInset = 21, kApartItemWidth = 62, kPlatterGap = 12;

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host || [sub isKindOfClass:SGRBarFade.class]) continue;
        sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    // An item with no title is drawn by UIKit as its glyph alone, centered, on a bar of the same height.
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);
    SGRSystemTabBar *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    UIView *active = SGRNavbarLitTab();
    if (![sources containsObject:active]) active = nil;
    for (UIView *source in sources) if (!active && isActive(source)) active = source;
    active = active ?: selectedSource(bar) ?: selectedSource(apartBar);

    NSMutableArray<UIView *> *main = [NSMutableArray array], *apart = [NSMutableArray array];
    for (UIView *source in sources) [(SGRTabIsApart(source) ? apart : main) addObject:source];
    if (!main.count) {
        main = [sources mutableCopy];
        [apart removeAllObjects];
    }
    if (apart.count && !apartBar) {
        apartBar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kApartBarKey, apartBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        apartBar.partner = bar;
        bar.partner = apartBar;
        [host addSubview:apartBar];
    }
    apartBar.hidden = !apart.count;
    if (apartBar.hidden) apartBar.sources = nil;

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    placeFade(stockBar, frame);
    CGRect mainFrame = host.bounds, apartFrame = CGRectZero;
    if (apart.count) {
        CGFloat apartWidth = MIN(width / 2, apart.count * kApartItemWidth + 2 * kPlatterInset);
        CGRectDivide(host.bounds, &apartFrame, &mainFrame, apartWidth, CGRectMaxXEdge);
        mainFrame.size.width += 2 * kPlatterInset - kPlatterGap;
    }
    if (!CGRectEqualToRect(bar.frame, mainFrame)) bar.frame = mainFrame;
    if (apart.count && !CGRectEqualToRect(apartBar.frame, apartFrame)) apartBar.frame = apartFrame;

    // The items go in once the bars are laid out at their frames. UIKit sizes an item's title by the platter it
    // is made in and never again when the bar grows, so items made while a bar was still a circle kept "…" for
    // their names at full width (harness/tabbar, `names`).
    [host layoutIfNeeded];
    BOOL missing = fillBar(bar, main, hideLabels);
    if (apart.count) missing |= fillBar(apartBar, apart, hideLabels);
    selectActive(bar, active);
    if (apart.count) selectActive(apartBar, active);
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    layoutDockAndCard(stockBar);
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - minimized

// A page scrolled down minimizes the bar (TabBarMinimize.x), the way the Music app's does. Spotify's tab bar
// container is a UIViewController of its own, not a UITabBarController, so UIKit's tabBarMinimizeBehavior has
// nothing to act on. Minimized, the two system bars give way to two round glass buttons at the bar's ends (the
// dock), and the now playing card takes the row between them (SGRDockNowPlayingCard). The expanded bar, split
// tabs and all, is left exactly as it is; the dock is a second look over it that the two fade between.
BOOL SGRTabBarMinimized(void) {
    return sg_minimized;
}

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    if (sg_minimized == minimized) return;
    // With nothing playing the row has no card to show, so the bar stays whole (one already minimized can come back).
    if (minimized && !SGRNowPlayingAvailable()) return;
    UIView *stockBar = sg_stockBar;
    // Spotify's regular width bar is not the glass one's row of tabs; it stays as it is.
    if (minimized && (!stockBar.window || stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact)) return;
    sg_minimized = minimized;
    SGLog(@"tab bar: %@", minimized ? @"minimized" : @"expanded");
    if (stockBar) applyMinimized(stockBar, animated);
}

#pragma mark - the dock

// Each end of the minimized bar is a glass circle the size of a tab's, with the first and last tab's glyph on it.
static const CGFloat kDockSize = 48, kDockGap = 8;

@interface SGRDockButton : UIVisualEffectView
@property (nonatomic, weak) UIView *source;
@property (nonatomic, readonly) UIImageView *glyph;
@end

@implementation SGRDockButton
- (instancetype)init {
    UIVisualEffect *effect = SGGlassEffect();
    if ([effect respondsToSelector:@selector(setInteractive:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, @selector(setInteractive:), YES);
    if (!(self = [super initWithEffect:effect])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGShapeGlass(self, kDockSize / 2, YES);
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    [self.contentView addSubview:_glyph];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _glyph.frame = self.bounds;
}
// A tap on a round button opens its tab and brings the whole bar back, as the Music app's does.
- (void)tapped {
    UIView *source = self.source;
    if (source) forwardTap(source);
    SGRSetTabBarMinimized(NO, YES);
}
@end

// Sets a view's place without touching its transform, so a scaled or animating view is not disturbed.
static void place(UIView *view, CGRect frame) {
    CGRect bounds = (CGRect){CGPointZero, frame.size};
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (!CGRectEqualToRect(view.bounds, bounds)) view.bounds = bounds;
    if (!CGPointEqualToPoint(view.center, center)) view.center = center;
}

// A bar's glass platter in `host`'s coordinates: the widest view of a bar's height inside the system bar, or the
// bar's own frame when UIKit has not built the platter yet.
static CGRect pillInBar(UIView *host, UITabBar *bar) {
    __block CGRect best = CGRectNull;
    __block CGFloat widest = 0;
    SGForEachView(bar, ^(UIView *v) {
        CGSize size = v.bounds.size;
        if (v == bar || size.width < bar.bounds.size.width * 0.5 || size.height < 44 || size.height > 72) return;
        if (size.width > widest) {
            widest = size.width;
            best = SGFrameIn(v, host);
        }
    });
    return CGRectIsNull(best) ? SGFrameIn(bar, host) : best;
}

static NSArray<SGRDockButton *> *dockButtons(UIView *stockBar) {
    NSArray *buttons = objc_getAssociatedObject(stockBar, &kDockKey);
    if (!buttons) {
        buttons = @[[SGRDockButton new], [SGRDockButton new]];
        for (SGRDockButton *button in buttons) {
            button.alpha = 0;
            button.userInteractionEnabled = NO;
        }
        objc_setAssociatedObject(stockBar, &kDockKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return buttons;
}

// The first and last tab's glyphs and places; the row left between them, in window coordinates. Minimized, the
// two buttons are 48 pt circles at the bar's ends. Expanded, they are where the bar draws its own: the first grows
// into the main bar's platter and the last into the split bar's circle (or, with no split tab, the trailing round
// of the one bar), so the circles read as the bar opening out. `circles` and `shapes` answer for the two states,
// left then right. When they are asked for, the caller animates the buttons; otherwise they are placed where the
// current state has them.
static CGRect layoutDock(UIView *stockBar, UIView *host, UITabBar *bar, UITabBar *apartBar, NSArray<UIView *> *sources,
                         CGRect circles[2], CGRect shapes[2]) {
    NSArray<SGRDockButton *> *buttons = dockButtons(stockBar);
    BOOL split = apartBar && !apartBar.hidden;
    CGRect mainPill = pillInBar(host, bar);
    CGRect trailPill = split ? pillInBar(host, apartBar) : mainPill;
    CGFloat middle = CGRectGetMidY(mainPill);
    CGRect left = CGRectMake(CGRectGetMinX(mainPill), middle - kDockSize / 2, kDockSize, kDockSize);
    CGRect right = CGRectMake(CGRectGetMaxX(trailPill) - kDockSize, middle - kDockSize / 2, kDockSize, kDockSize);
    CGRect shape0, shape1;
    if (split) {
        shape0 = mainPill;
        shape1 = trailPill;
    } else {
        CGFloat full = mainPill.size.height;
        CGRect fullRight = CGRectMake(CGRectGetMaxX(mainPill) - full, CGRectGetMinY(mainPill), full, full);
        shape0 = CGRectMake(CGRectGetMinX(mainPill), CGRectGetMinY(mainPill), CGRectGetMinX(fullRight) - kDockGap - CGRectGetMinX(mainPill), full);
        shape1 = fullRight;
    }
    if (circles) { circles[0] = left; circles[1] = right; }
    if (shapes) { shapes[0] = shape0; shapes[1] = shape1; }
    UIColor *accent = SGRAccent();
    for (NSUInteger i = 0; i < 2; i++) {
        SGRDockButton *button = buttons[i];
        UIView *source = i == 0 ? sources.firstObject : (sources.count > 1 ? sources.lastObject : nil);
        button.source = source;
        if (button.superview != host) [host addSubview:button];
        if (!circles) place(button, sg_minimized ? (i == 0 ? left : right) : (i == 0 ? shape0 : shape1));
        else if (CGRectIsEmpty(button.bounds)) place(button, sg_minimized ? (i == 0 ? shape0 : shape1) : (i == 0 ? left : right));
        if (!source) continue;
        BOOL active = isActive(source);
        UIImage *image = glyphOf(source, active);
        if (image && button.glyph.image != image) button.glyph.image = image;
        UIColor *tint = active ? accent : [UIColor colorWithWhite:1 alpha:0.92];
        if (![button.glyph.tintColor isEqual:tint]) button.glyph.tintColor = tint;
        button.accessibilityLabel = labelIn(source).text;
    }
    buttons[1].hidden = sources.count < 2;
    CGRect row = CGRectMake(CGRectGetMaxX(left) + kDockGap, middle - kDockSize / 2,
                            CGRectGetMinX(right) - CGRectGetMaxX(left) - 2 * kDockGap, kDockSize);
    return [host convertRect:row toView:nil];
}

// Keeps the dock buttons placed and the card docked as the bar lays out again (a tab change, a new track), without
// starting the open/close animation. Called from the end of syncBar.
static void layoutDockAndCard(UIView *stockBar) {
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    if (!host.window) return;
    UITabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    UITabBar *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    CGRect row = layoutDock(stockBar, host, bar, apartBar, tabItems(stockBar), NULL, NULL);
    if (sg_minimized) SGRDockNowPlayingCard(YES, row, host, NO);
}

// Minimizing gathers the bar into its two ends; expanding is the reverse, and the buttons are what moves: the first
// widens into the main bar's platter and the last into the split bar's circle, and the bars' own drawing takes over
// as they arrive, so the circles read as the bar opening out rather than one thing replaced by another.
static void applyMinimized(UIView *stockBar, BOOL animated) {
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    SGRSystemTabBar *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    if (!host || !bar || !host.window) return;
    BOOL minimized = sg_minimized;
    CGRect circles[2], shapes[2];
    CGRect row = layoutDock(stockBar, host, bar, apartBar, tabItems(stockBar), circles, shapes);
    // Blocks cannot capture C arrays under ARC; copy the values into scalar locals.
    CGRect circle0 = circles[0], circle1 = circles[1], shape0 = shapes[0], shape1 = shapes[1];
    NSArray<SGRDockButton *> *buttons = dockButtons(stockBar);
    bar.userInteractionEnabled = !minimized;
    apartBar.userInteractionEnabled = !minimized;
    for (SGRDockButton *button in buttons) button.userInteractionEnabled = minimized;
    SGRDockNowPlayingCard(minimized, row, host, animated);

    void (^move)(void) = ^{
        for (NSUInteger i = 0; i < 2; i++) {
            place(buttons[i], minimized ? (i == 0 ? circle0 : circle1) : (i == 0 ? shape0 : shape1));
            [buttons[i] layoutIfNeeded];
        }
    };
    // A button comes in from where the other state had it, unless it is already showing.
    void (^start)(void) = ^{
        for (NSUInteger i = 0; i < 2; i++) {
            if (buttons[i].alpha > 0.01) continue;
            place(buttons[i], minimized ? (i == 0 ? shape0 : shape1) : (i == 0 ? circle0 : circle1));
            [buttons[i] layoutIfNeeded];
        }
    };
    void (^settle)(void) = ^{
        bar.alpha = minimized ? 0 : 1;
        apartBar.alpha = minimized ? 0 : 1;
        for (SGRDockButton *button in buttons) {
            button.alpha = minimized ? 1 : 0;
            button.glyph.alpha = 1;
        }
    };
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:^{ start(); move(); settle(); }];
        return;
    }
    [UIView performWithoutAnimation:start];
    // Springs with no bounce: a scroll turned around mid-way starts from where the buttons are.
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:move completion:nil];
    UIViewAnimationOptions fade = options | UIViewAnimationOptionCurveEaseInOut;
    if (minimized) {
        [UIView animateWithDuration:0.18 delay:0 options:fade animations:^{ bar.alpha = 0; apartBar.alpha = 0; } completion:nil];
        [UIView animateWithDuration:0.2 delay:0 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.alpha = 1;
        } completion:nil];
        [UIView animateWithDuration:0.2 delay:0.2 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.glyph.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.12 delay:0 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.glyph.alpha = 0;
        } completion:nil];
        [UIView animateWithDuration:0.25 delay:0.18 options:fade animations:^{ bar.alpha = 1; apartBar.alpha = 1; } completion:nil];
        [UIView animateWithDuration:0.22 delay:0.26 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.alpha = 0;
        } completion:nil];
    }
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class] && ![sub isKindOfClass:SGRBarFade.class]) [sub layoutIfNeeded];
    }
    holdHome((UIView *)self);
    syncBar((UIView *)self);
    SGRLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Another tab brings the minimized bar back (HIG, Tab bars).
        SGRSetTabBarMinimized(NO, YES);
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
// The message bar coming or going changes the view's safe area before Spotify lays the bar out for it,
// so the room follows in that same pass, and inside the message bar's animation.
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

// Spotify's own fade under its bar, 219 pt down to black from 9.1.90 (TabBarGradientView), stacked with SGRBarFade
// into a band near black over the page's foot. SGRBarFade is the redesign's, so Spotify's stays clear.
%group SpotifyBarFade
%hook _TtC23NavigationUI_TabBarImpl18TabBarGradientView
- (void)didMoveToWindow {
    %orig;
    ((UIView *)self).alpha = 0;
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(0);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (objc_getClass("_TtC23NavigationUI_TabBarImpl18TabBarGradientView")) %init(SpotifyBarFade);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
