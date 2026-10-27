// The redesign's now playing bar: the album-colored card becomes a glass card with round artwork and the
// progress line under the text. Spotify's own labels, buttons and gestures stay in place.
//
// The full screen player morphs the bar's own card and artwork into the cover art. The bar was
// written to hand itself back to Spotify for that animation, from NowPlaying_ViewPageImpl's
// Show/CloseFullscreenAnimatedTransitioning, but Spotify 9.1.78 never runs the player through those,
// so the handback never happened and is gone; if the morph ever reads as a cut, the place to start is
// Shared/Player/PlayerEvents.h, which does fire. What does move with the player is a stand-in of the
// bar, which BarTransition.x keeps glass behind.
//
// Tree (trees/home.txt): NowPlayingBarContainerViewController.view 402x56 > NowPlayingBarViewController.view
//   at {8,0} 386x56 > UIView 386x56 (the painted card) > artwork 40x40 r=4, title stack,
//   progress line 370x2 at the bottom. The glass pane goes on the container's view.
//
// In a Jam Spotify puts a "Jam by ..." strip on the bar, a SwiftUI _UIHostingView of
// Jam_AttachmentsImpl.JamHatElement as wide as the card and 44pt high, and grows the bar by its height
// (386x100, the track card at y = 44). It paints the strip, or a view around the strip and the track, as
// well, so the card is the painted view that holds the track and has no strip in it. The strip stays out
// of the card's glass and gets a pane of its own above it, since its own paint goes clear with the rest.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Settings/SGMarquee.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "NowPlayingBar.h"
#import "Redesigned/Navbar/Navbar.h"
#import <objc/message.h>

static const CGFloat kCardRadius = 24;
// The strip's pane is this much smaller than the strip at each end, so a gap parts it from the card's glass.
static const CGFloat kStripInset = 4;
static char kGlassKey, kStripGlassKey;
static __weak UIView *sg_card;
static CGRect sg_stripFrame;
static __weak UIVisualEffectView *sg_cardGlass;
static __weak UIView *sg_cardArtwork;
static __weak UIView *sg_progress;
static __weak UIViewController *sg_container;
// The dock: the mod's own pill (SGRMiniPlayer) stands in the minimized tab bar's row while the real bar fades out.
static BOOL sg_docked;
static CGRect sg_dockRow;   // window coordinates
static __weak UIView *sg_dockHost;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    UIVisualEffectView *glass = sg_cardGlass;
    if (!glass.superview || !glass.window || !host) return CGRectNull;
    if (radius) *radius = MIN(kCardRadius, glass.bounds.size.height / 2);
    return [host convertRect:glass.bounds fromView:glass];
}

CGRect SGRNowPlayingArtworkFrameIn(UIView *host) {
    UIView *artwork = sg_cardArtwork;
    if (!artwork.window || !host) return CGRectNull;
    return [host convertRect:artwork.bounds fromView:artwork];
}

// The Jam strip. The height keeps out a view of the same module that can hold the track card too.
static BOOL isStrip(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return view.bounds.size.height <= 60 && [name containsString:@"AttachmentsImpl"] && [name containsString:@"Hat"];
}

static BOOL inStrip(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) if (isStrip(v)) return YES;
    return NO;
}

static UIView *stripIn(UIView *root) {
    __block UIView *strip = nil;
    SGForEachView(root, ^(UIView *v) { if (!strip && isStrip(v)) strip = v; });
    return strip;
}

// What holds the track on the bar: the title and artist block, else the artwork (a 36 to 48pt square that
// is not a button), never anything in the strip. Nil when neither is there.
static UIView *trackMarker(UIView *bar) {
    __block UIView *info = nil, *artwork = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (info || inStrip(v, bar)) return;
        if ([NSStringFromClass(v.class) containsString:@"InformationContainer"]) info = v;
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!artwork && square && ![v isKindOfClass:UIControl.class]) artwork = v;
    });
    return info ?: artwork;
}

// A card holds the track and has no strip in it; one with the strip in it only when there is no other.
// Among equals the largest, which outside a Jam is the card it always was.
static BOOL isGoodCard(UIView *card, UIView *bar, UIView *marker) {
    return SGIsInside(card, bar) && !inStrip(card, bar) && (!marker || [marker isDescendantOfView:card]);
}

static UIView *chooseCard(UIView *bar, UIView *marker) {
    UIView *best = nil;
    BOOL bestHasStrip = NO;
    CGFloat bestArea = 0;
    for (UIView *v in sgr_nowPlayingPainted) {
        // Card sized: the paint itself has gone clear by now.
        if (!SGLooksLikeCard(v, UIColor.whiteColor.CGColor) || !isGoodCard(v, bar, marker)) continue;
        BOOL hasStrip = stripIn(v) != nil;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        BOOL better = !best || (hasStrip != bestHasStrip ? !hasStrip : area > bestArea);
        if (!better) continue;
        best = v;
        bestHasStrip = hasStrip;
        bestArea = area;
    }
    return best;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0 || inStrip(v, bar)) return;
        CGFloat width = v.bounds.size.width;
        BOOL content = ([v isKindOfClass:UIImageView.class] && width >= 20 && width <= 120)
            || [v isKindOfClass:UILabel.class]
            || ([v isKindOfClass:UIControl.class] && width <= 100);
        if (content) box = CGRectUnion(box, SGFrameIn(v, target));
    });
    return CGRectIsNull(box) ? box : CGRectInset(box, -10, -8);
}

static void roundView(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

static void restyleCardContent(UIView *card) {
    SGForEachView(card, ^(UIView *v) {
        if (inStrip(v, card)) return;
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!square || v.layer.cornerRadius <= 0) return;
        if (v.layer.cornerRadius >= size.width / 2) {
            if (!sg_cardArtwork) sg_cardArtwork = v;
            return;
        }
        UIView *outer = v;
        for (UIView *u = v; u && u != card && CGSizeEqualToSize(u.bounds.size, size); u = u.superview) {
            roundView(u, size.width / 2);
            u.clipsToBounds = YES;
            outer = u;
        }
        sg_cardArtwork = outer;
    });
    __block UIView *progress = sg_progress;
    if (![progress isDescendantOfView:card]) {
        progress = nil;
        SGForEachView(card, ^(UIView *v) {
            CGRect f = v.frame;
            if (!progress && !inStrip(v, card) && f.size.height <= 3 && f.size.width >= 200 && v.superview.bounds.size.height >= 40) progress = v;
        });
        sg_progress = progress;
    }
    // Under the text, 226pt on a full width card, shorter on the one in the minimized tab bar.
    CGRect target = CGRectMake(52, card.bounds.size.height - 6, MAX(0, card.bounds.size.width - 160), 2);
    if (progress && !CGRectEqualToRect(progress.frame, target)) {
        progress.frame = target;
        [progress setNeedsLayout];
        [progress layoutIfNeeded];
    }
}

// The strip's own pane, a strip high less the gaps, on the card's side the strip is on. It is measured from
// the card's settled frame and the strip's height, not from the strip's frame: Spotify animates the strip
// in, and a pane taken from it mid-way sat about 12pt off and cut its ⋯ button. The glass comes in and goes
// by its effect, never by alpha (SGRGlass.h).
static void placeStripGlass(UIView *host, UIView *strip, CGRect card, BOOL above) {
    UIVisualEffectView *pane = objc_getAssociatedObject(host, &kStripGlassKey);
    if (!strip) {
        if (pane.effect) SGRAnimate(SGRMotionExit, ^{ SGRShowGlass(pane, NO); }, nil);
        return;
    }
    BOOL made = pane != nil;
    pane = SGGlassFor(host, &kStripGlassKey);
    if (!made) {
        pane.effect = nil;
        pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    CGFloat height = strip.bounds.size.height;
    CGRect frame = CGRectMake(card.origin.x, above ? CGRectGetMinY(card) - height : CGRectGetMaxY(card), card.size.width, height);
    pane.frame = CGRectInset(frame, 0, kStripInset);
    SGShapeGlass(pane, MIN(kCardRadius, pane.bounds.size.height / 2), NO);
    if (!pane.effect) SGRAnimate(SGRMotionRespond, ^{ SGRShowGlass(pane, YES); }, nil);
}

#pragma mark - the dock's pill

// Minimized, the card does not shrink into the row: scaled to fit it, its text and cover come out too small to
// read. The row gets a pill of the mod's own, as high as the round buttons beside it, with only what is needed
// at that size: the cover, the title on one line and play/pause. It reads the track off the player and the cover
// off the card, and a tap on it is passed on to Spotify's own card (SGRFireTapRecognizers) or to the player.
static const CGFloat kPillHeight = 48, kPillInset = 4, kPillGap = 10, kToggleWidth = 44;

static void openPlayer(void);
static void togglePlayback(void);

@interface SGRMiniPlayer : UIVisualEffectView
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) UIView *titleClip;
@property (nonatomic, readonly) UIButton *toggle;
@property (nonatomic, readonly) UIButton *open;
@property (nonatomic) BOOL paused;
- (void)showTitle:(NSString *)title cover:(UIImage *)cover paused:(BOOL)paused;
// Starts a long title scrolling again (an animation does not outlive the app in the background or the pill off screen).
- (void)resumeMarquee;
@end

@implementation SGRMiniPlayer {
    NSString *_marqueeKey;
}

- (instancetype)init {
    UIVisualEffect *effect = SGGlassEffect();
    if ([effect respondsToSelector:@selector(setInteractive:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, @selector(setInteractive:), YES);
    if (!(self = [super initWithEffect:effect])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGShapeGlass(self, kPillHeight / 2, YES);

    // Behind everything: a touch anywhere on the pill but the button opens the player, and VoiceOver finds one element.
    _open = [UIButton buttonWithType:UIButtonTypeCustom];
    [_open addTarget:self action:@selector(opened) forControlEvents:UIControlEventTouchUpInside];
    _open.accessibilityTraits = UIAccessibilityTraitButton;
    [self.contentView addSubview:_open];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _cover.userInteractionEnabled = NO;
    [self.contentView addSubview:_cover];

    // A title that fits stays put; a longer one slides to its end and back so it can be read whole.
    _titleClip = [UIView new];
    _titleClip.clipsToBounds = YES;
    _titleClip.userInteractionEnabled = NO;
    [self.contentView addSubview:_titleClip];
    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _title.textColor = SGRPrimary();
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _title.numberOfLines = 1;
    _title.userInteractionEnabled = NO;
    [_titleClip addSubview:_title];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumeMarquee) name:UIApplicationDidBecomeActiveNotification object:nil];

    _toggle = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggle.tintColor = SGRPrimary();
    [_toggle addTarget:self action:@selector(toggled) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_toggle];
    [self setPaused:YES];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat side = bounds.size.height - 2 * kPillInset;
    _open.frame = bounds;
    // A circle, as the card's round artwork is.
    _cover.frame = CGRectMake(kPillInset, kPillInset, side, side);
    _cover.layer.cornerRadius = side / 2;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    CGFloat toggleWidth = MIN(kToggleWidth, bounds.size.width / 3);
    _toggle.frame = CGRectMake(bounds.size.width - toggleWidth - 6, 0, toggleWidth, bounds.size.height);
    CGFloat left = CGRectGetMaxX(_cover.frame) + kPillGap;
    _titleClip.frame = CGRectMake(left, 0, MAX(0, CGRectGetMinX(_toggle.frame) - kPillGap - left), bounds.size.height);
    [self layoutTitle];
}

static const CGFloat kMarqueeSpeed = 32, kMarqueePause = 1.4, kMarqueeFade = 18;

- (void)layoutTitle {
    CGFloat clip = _titleClip.bounds.size.width, height = _titleClip.bounds.size.height;
    CGFloat text = ceil([_title.text ?: @"" sizeWithAttributes:@{NSFontAttributeName: _title.font}].width);
    BOOL overflows = text > clip + 0.5 && clip > 0;
    BOOL moves = overflows && !UIAccessibilityIsReduceMotionEnabled();
    // Under Reduce Motion a long title is cut with an ellipsis instead.
    CGRect frame = CGRectMake(0, 0, moves ? text : clip, height);
    NSString *key = [NSString stringWithFormat:@"%@|%.1f|%d", _title.text, clip, moves];
    if (!CGRectEqualToRect(_title.frame, frame)) _title.frame = frame;
    BOOL running = [_title.layer animationForKey:@"marquee"] != nil;
    if ([key isEqualToString:_marqueeKey] && running == moves) return;
    _marqueeKey = key;
    [_title.layer removeAnimationForKey:@"marquee"];
    // The right edge fades out while a title runs on past it.
    if (moves) {
        CAGradientLayer *mask = [CAGradientLayer layer];
        mask.frame = _titleClip.bounds;
        mask.startPoint = CGPointMake(0, 0.5);
        mask.endPoint = CGPointMake(1, 0.5);
        mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        mask.locations = @[@0, @(MAX(0.5, 1 - kMarqueeFade / clip)), @1];
        _titleClip.layer.mask = mask;
    } else {
        _titleClip.layer.mask = nil;
    }
    if (!moves) return;
    CGFloat travel = text - clip + kMarqueeFade / 2;
    CGFloat run = travel / kMarqueeSpeed, total = 2 * kMarqueePause + 2 * run;
    CAKeyframeAnimation *slide = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    slide.values = @[@0, @0, @(-travel), @(-travel), @0];
    slide.keyTimes = @[@0, @(kMarqueePause / total), @((kMarqueePause + run) / total), @((2 * kMarqueePause + run) / total), @1];
    slide.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
    ];
    slide.duration = total;
    slide.repeatCount = HUGE_VALF;
    slide.removedOnCompletion = NO;
    [_title.layer addAnimation:slide forKey:@"marquee"];
}

- (void)resumeMarquee {
    _marqueeKey = nil;
    [self setNeedsLayout];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [UIImage systemImageNamed:paused ? @"play.fill" : @"pause.fill" withConfiguration:config];
    if (_toggle.currentImage != glyph) [_toggle setImage:glyph forState:UIControlStateNormal];
    _toggle.accessibilityLabel = paused ? @"Play" : @"Pause";
}

- (void)showTitle:(NSString *)title cover:(UIImage *)cover paused:(BOOL)paused {
    if (title.length && ![_title.text isEqualToString:title]) {
        _title.text = title;
        [self setNeedsLayout];
    }
    _open.accessibilityLabel = _title.text;
    if (_cover.image != cover) _cover.image = cover;
    if (_paused != paused) {
        // The glyph swaps in place, so the button does not jump while the track goes on.
        [UIView transitionWithView:_toggle duration:SGRReduceMotion() ? 0 : 0.15 options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ [self setPaused:paused]; } completion:nil];
    }
}

- (void)opened { openPlayer(); }
- (void)toggled { togglePlayback(); }
@end

static SGRMiniPlayer *sg_mini;
static void refreshMini(void);

static SGRMiniPlayer *miniPlayer(void) {
    if (!sg_mini) {
        sg_mini = [SGRMiniPlayer new];
        sg_mini.alpha = 0;
        sg_mini.userInteractionEnabled = NO;
    }
    return sg_mini;
}

// The cover the card shows, which Spotify loads a moment after a new track: read off the card on each of its passes.
static UIImage *cardCover(void) {
    __block UIImage *image = nil;
    SGForEachView(sg_cardArtwork, ^(UIView *v) {
        if (!image && [v isKindOfClass:UIImageView.class]) image = ((UIImageView *)v).image;
    });
    return image;
}

static UIImage *currentCover(void) {
    SPTPlayerState *state = SGPlayerState();
    NSString *artworkTrack = nil;
    UIImage *artwork = SGRNowPlayingArtwork(&artworkTrack, NULL);
    if (artwork && [artworkTrack isEqualToString:SGURIString(state.track.URI)]) return artwork;
    return cardCover();
}

static BOOL hasTrack(void) {
    return SGPlayerState().track.trackTitle.length > 0;
}

BOOL SGRNowPlayingAvailable(void) {
    return hasTrack();
}

static void refreshMini(void) {
    SGRMiniPlayer *mini = sg_mini;
    if (!mini) return;
    SPTPlayerState *state = SGPlayerState();
    [mini showTitle:state.track.trackTitle cover:currentCover() paused:state.isPaused];
}

static void togglePlayback(void) {
    id<SPTPlayer> player = SGKaraokePlayer();
    if (!player) return;
    if (SGPlayerState().isPaused) [player resume:nil];
    else [player pause:nil];
}

// A tap on the pill is the card's own: Spotify's tap recognizer sits on the card or a view around it, fired from
// the card outwards so the play button's own recognizer is never reached.
static void openPlayer(void) {
    UIView *stop = sg_container.viewIfLoaded;
    for (UIView *v = sg_card ?: sg_cardArtwork; v; v = v.superview) {
        if (SGRFireTapRecognizers(v)) return;
        if (v == stop) break;
    }
    SGLog(@"now playing pill: no tap recognizer found on the card to open the player with");
}

@interface SGRMiniPlayerWatcher : NSObject <SGPlayerStateObserver>
@end

static NSUInteger sg_miniRefreshGeneration, sg_miniTrackGeneration;
static NSString *sg_miniTrackURI;

@implementation SGRMiniPlayerWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSUInteger refreshGeneration = ++sg_miniRefreshGeneration;
    NSString *trackURI = SGURIString(state.track.URI);
    BOOL trackChanged = ![trackURI isEqualToString:sg_miniTrackURI];
    if (trackChanged) {
        sg_miniTrackURI = [trackURI copy];
        sg_miniTrackGeneration++;
    }
    NSUInteger generation = sg_miniTrackGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (refreshGeneration != sg_miniRefreshGeneration) return;
        // The queue ended with the bar minimized: the pill has nothing left to show, so the whole bar comes back.
        if (!hasTrack() && SGRTabBarMinimized()) SGRSetTabBarMinimized(NO, YES);
        refreshMini();
    });
    if (!trackChanged) return;
    // A new track's cover reaches the card a little after the state does.
    for (NSNumber *delay in @[@0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == sg_miniTrackGeneration) refreshMini();
        });
    }
}
@end

static SGRMiniPlayerWatcher *sg_miniWatcher;
static id sg_artworkObserver;

static void applyDock(BOOL animated) {
    UIView *view = sg_container.viewIfLoaded;
    UIView *host = sg_dockHost;
    UIVisualEffectView *glass = sg_cardGlass;
    if (!view || !host || !host.window || glass.superview != view) return;

    // Nothing is playing (or the player has not reported): there is no pill, and the card stays as Spotify has it.
    BOOL docked = sg_docked && hasTrack();
    SGRMiniPlayer *mini = miniPlayer();
    if (mini.superview != host) [host addSubview:mini];
    refreshMini();

    CGRect card = [host convertRect:glass.bounds fromView:glass];
    CGRect row = [host convertRect:sg_dockRow fromView:nil];
    // The pill is as high as the buttons beside it, and keeps their middle.
    CGRect pill = CGRectMake(row.origin.x, CGRectGetMidY(row) - kPillHeight / 2, row.size.width, kPillHeight);
    CGRect target = docked ? pill : card;
    CGFloat pillAlpha = docked ? 1 : 0, cardAlpha = docked ? 0 : 1;

    BOOL settled = CGRectEqualToRect(mini.frame, target) && mini.alpha == pillAlpha && view.alpha == cardAlpha;
    mini.userInteractionEnabled = docked;
    view.userInteractionEnabled = !docked;
    if (settled) return;

    // Out of sight, the pill waits on the card, so it comes out of it on the way down and goes back into it on the way up.
    if (mini.alpha < 0.01 && docked) {
        [mini resumeMarquee];
        [UIView performWithoutAnimation:^{
            mini.frame = card;
            [mini layoutIfNeeded];
        }];
    }
    void (^apply)(void) = ^{
        mini.frame = target;
        [mini layoutIfNeeded];
        mini.alpha = pillAlpha;
        view.alpha = cardAlpha;
    };
    if (!animated) {
        [UIView performWithoutAnimation:apply];
        return;
    }
    // A spring with no bounce: nothing was thrown, and it starts from wherever the pill is now if it is turned around.
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:apply completion:nil];
}

void SGRDockNowPlayingCard(BOOL docked, CGRect row, UIView *host, BOOL animated) {
    sg_docked = docked;
    if (docked) sg_dockRow = row;
    if (host) sg_dockHost = host;
    applyDock(animated && !UIAccessibilityIsReduceMotionEnabled());
}

// The Music app's two lines, the title over the artists, in place of Spotify's "title • artists" and the
// device line under it; the title alone in the minimized row. Each swipe page holds its own track's labels,
// so the text is read from them and drawn over them page by page. The page reads its own VoiceOver label.
static NSString *const kPageId = @"now-playing-bar-page";
static NSString *const kUnitId = @"Components.UI.PageInformationUnitNowPlayingBar";
static NSString *const kDeviceLineId = @"now-plaging-bar-connect-content";   // Spotify's spelling
static NSString *const kBullet = @" • ";
static char kTextKey;

@interface SGRBarText : UIView
@property (nonatomic, readonly) SGMarqueeLabel *title, *artists;
@property (nonatomic) BOOL inRow;
@end

@implementation SGRBarText
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _title = [SGMarqueeLabel new];
    _title.textColor = SGRPrimary();
    _title.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    _artists = [SGMarqueeLabel new];
    _artists.textColor = SGRSecondary();
    _artists.font = SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryLarge);
    [self addSubview:_title];
    [self addSubview:_artists];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistsHeight = ceil(_artists.font.lineHeight);
    BOOL two = !_inRow && _artists.text.length;
    // The lines share 2pt of their leading, set as close as the Music app sets its card's.
    CGFloat shared = 2;
    CGFloat top = round((size.height - titleHeight - (two ? artistsHeight - shared : 0)) / 2);
    _title.frame = CGRectMake(0, top, size.width, titleHeight);
    _artists.frame = CGRectMake(0, top + titleHeight - shared, size.width, artistsHeight);
    _artists.alpha = two ? 1 : 0;
}
@end

static NSString *marqueeText(UIView *marquee) {
    for (UIView *sub in marquee.subviews) if ([sub isKindOfClass:UILabel.class]) return ((UILabel *)sub).text;
    return nil;
}

// Not hidden or faded by Spotify between the view and the unit; the unit's own children are faded by this file.
static BOOL inSight(UIView *view, UIView *unit) {
    for (UIView *v = view; v && v != unit; v = v.superview) {
        if (v.hidden || (v.alpha < 0.01 && v.superview != unit)) return NO;
    }
    return YES;
}

static void placeText(UIView *page) {
    // The cell lays itself out before its content view places Spotify's text, so the text is placed first.
    [page layoutIfNeeded];
    __block UIView *unit = nil;
    SGForEachView(page, ^(UIView *v) {
        if (!unit && [v.accessibilityIdentifier isEqualToString:kUnitId]) unit = v;
    });
    // Spotify lays a page out two ways. With a device line under it, the unit's first marquee is "title • artists"
    // and a later one, hidden, holds the artists alone. Without one, the first is the title and the next one in
    // sight is the artists. A promotional line, held at no alpha, is never the artists.
    __block NSString *line = nil, *artists = nil, *shown = nil;
    if (unit) SGForEachView(unit, ^(UIView *v) {
        if (![v.accessibilityIdentifier isEqualToString:@"Encore.MarqueeLabel"]) return;
        NSString *text = marqueeText(v);
        if (!line) {
            line = text;
            return;
        }
        if (!text.length) return;
        if (!artists && [line hasSuffix:[kBullet stringByAppendingString:text]]) artists = text;
        if (!shown && inSight(v, unit)) shown = text;
    });
    if (!line.length) return;
    NSString *title = line;
    if (artists) {
        title = [line substringToIndex:line.length - artists.length - kBullet.length];
    } else {
        NSRange bullet = [line rangeOfString:kBullet];
        if (bullet.location != NSNotFound) {
            title = [line substringToIndex:bullet.location];
            artists = [line substringFromIndex:NSMaxRange(bullet)];
        } else {
            artists = shown;
        }
    }

    SGRBarText *text = objc_getAssociatedObject(page, &kTextKey);
    BOOL made = !text;
    if (made) {
        text = [SGRBarText new];
        objc_setAssociatedObject(page, &kTextKey, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Inside Spotify's unit, so the text moves and fades with it as Spotify slides a page's in and out: the page's
    // height, which the card shows whole, and a line of text wide.
    CGRect frame = CGRectMake(0, -SGFrameIn(unit, page).origin.y, unit.bounds.size.width, page.bounds.size.height);
    BOOL inRow = NO;
    void (^place)(void) = ^{
        if (text.superview != unit) [unit addSubview:text];
        else if (unit.subviews.lastObject != text) [unit bringSubviewToFront:text];
        if (!CGRectEqualToRect(text.frame, frame)) text.frame = frame;
        text.title.text = title;
        text.artists.text = artists ?: @"";
        // Every pass: the artists can come in after the title.
        text.inRow = inRow;
        [text setNeedsLayout];
        [text layoutIfNeeded];
    };
    // A new page's text is placed where it belongs, never grown from nothing inside the bar's animation.
    if (made) [UIView performWithoutAnimation:place];
    else place();
    for (UIView *sub in unit.subviews) if (sub != text && sub.alpha > 0) sub.alpha = 0;
}

static void placeTexts(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = v.accessibilityIdentifier;
        if ([name isEqualToString:kPageId]) placeText(v);
        else if ([name isEqualToString:kDeviceLineId] && v.alpha > 0) v.alpha = 0;
    });
}

static void styleNowPlayingBar(UIViewController *container) {
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sg_container = container;
    if (!sgr_nowPlayingPainted) sgr_nowPlayingPainted = [NSHashTable weakObjectsHashTable];
    sgr_nowPlayingRoot = bar;

    // What is painted now, before it goes clear; SGRRepaint.x adds what Spotify paints later. Its size is
    // judged when the card is chosen: in a Jam the card can still be unsized here (harness/tabbar).
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UIVisualEffectView.class] && !SGKeepsColor(v) && SGIsVisibleColor(v.layer.backgroundColor)) [sgr_nowPlayingPainted addObject:v];
    });
    // The card stays while it still holds the track with no strip in it, whatever Spotify paints after.
    UIView *marker = trackMarker(bar);
    UIView *card = sg_card;
    if (!card || !isGoodCard(card, bar, marker) || stripIn(card)) card = sg_card = chooseCard(bar, marker);

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);

    UIView *strip = stripIn(bar);
    if (strip && (strip.hidden || strip.alpha < 0.01 || !strip.window)) strip = nil;
    // Spotify lays the strip out after the bar and moves it in, so the bar is styled again a moment after
    // the strip has moved, until it stays put.
    CGRect stripFrame = strip ? SGFrameIn(strip, container.view) : CGRectZero;
    if (!CGRectEqualToRect(stripFrame, sg_stripFrame)) {
        sg_stripFrame = stripFrame;
        UIView *host = container.view;
        dispatch_async(dispatch_get_main_queue(), ^{ [host setNeedsLayout]; });
    }
    if (strip.bounds.size.height < 1) strip = nil;
    // The Music app's two lines over Spotify's own text, drawn page by page (placeText), every pass.
    placeTexts(bar);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    // The strip comes out of the card's glass from its side: all of it when the card is a view around both,
    // else as much as overlaps.
    BOOL stripAbove = NO;
    if (strip) {
        stripAbove = CGRectGetMidY(stripFrame) < CGRectGetMidY(frame);
        CGFloat cut = card && [strip isDescendantOfView:card] ? strip.bounds.size.height : CGRectIntersection(frame, stripFrame).size.height;
        frame.size.height -= cut;
        if (stripAbove) frame.origin.y += cut;
    }
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }

    UIVisualEffectView *glass = SGGlassFor(container.view, &kGlassKey);
    // Dark whatever the system is set to: the bar is outside the navigation stacks Spotify makes dark, and
    // took the system's light glass on a phone in light mode (TabBar.x).
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_cardGlass = glass;
    glass.frame = frame;
    SGShapeGlass(glass, radius, NO);
    placeStripGlass(container.view, strip, frame, stripAbove);
    // A new track can change the card's size and bring its cover; the pill in the dock follows them.
    if (sg_docked) applyDock(NO);
    else refreshMini();

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"now playing card %@ at %@ (bar %@, container %@)", card.class, NSStringFromCGRect(frame),
              NSStringFromCGRect(bar.frame), NSStringFromCGRect(container.view.bounds));
    });
    static dispatch_once_t jamOnce;
    if (strip) dispatch_once(&jamOnce, ^{
        SGLog(@"now playing card in a Jam: %@ at %@, strip %@ at %@ (bar %@)", card.class, NSStringFromCGRect(frame), strip.class,
              NSStringFromCGRect(SGFrameIn(strip, container.view)), NSStringFromCGRect(bar.frame));
    });
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    styleNowPlayingBar((UIViewController *)self);
}
%end

// A page lays out again when Spotify moves its text, which it does after the first pass at launch.
%hook _TtC18NowPlaying_BarImpl17InformationCellV2
- (void)layoutSubviews {
    %orig;
    if (sgr_nowPlayingRoot) placeText((UIView *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl15InformationCell
- (void)layoutSubviews {
    %orig;
    if (sgr_nowPlayingRoot) placeText((UIView *)self);
}
%end

// A page's marquee lays out again when Spotify gives it a new track, which nothing else of the bar's does.
%hook _TtCE14Encore_TextKitO16EncoreFoundation6Encore12MarqueeLabel
- (void)layoutSubviews {
    %orig;
    UIView *root = sgr_nowPlayingRoot;
    if (!root || ![(UIView *)self isDescendantOfView:root]) return;
    for (UIView *v = (UIView *)self; v && v != root; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageId]) {
            placeText(v);
            return;
        }
    }
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if ([NSStringFromClass(parent.class) containsString:@"NowPlayingBarContainer"]) styleNowPlayingBar(parent);
}
%end

// Spotify's save button flag, forced off while the redesign's own "Hide the like button" switch is on. The native
// look's save button row writes the same flag under its own key, so the redesign keeps its switch on its own key.
%ctor {
    SGFlagForcer hidesLike = ^id(NSString *key) {
        return SGRedesignedUIStored() && SGHidden(SGRKeyBarHideLike) && [key isEqualToString:@"ios-feature-nowplayingbar.add_button"] ? @NO : nil;
    };
    SGRegisterFlagForcer(YES, hidesLike, hidesLike);
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    // The dock's pill reads the track off the player: a new track or play/pause refreshes its title, cover and glyph.
    sg_miniWatcher = [SGRMiniPlayerWatcher new];
    SGAddPlayerStateObserver(sg_miniWatcher);
    sg_artworkObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification
                                                                         object:nil
                                                                          queue:NSOperationQueue.mainQueue
                                                                     usingBlock:^(NSNotification *note) {
        if ([note.userInfo[@"trackURI"] isEqualToString:SGURIString(SGPlayerState().track.URI)]) refreshMini();
    }];
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
        @"_TtCE14Encore_TextKitO16EncoreFoundation6Encore12MarqueeLabel",
        @"_TtC18NowPlaying_BarImpl17InformationCellV2",
    ]);
}
