// Player redesign: Animated artwork, the track's Canvas or its album's Apple Music cover looping muted over
// Fluid artwork and under the rest of the player, found the way the lock screen finds its clip. Fluid
// artwork shows until the clip can be drawn, for a track without one, and while the lyrics are up.
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Player.h"

static const NSTimeInterval kFadeIn = 0.6, kFadeOut = 0.45;
// The dim holds the brighter part of a clip (the 75th percentile of a few frames' linear luminance) under
// this, where white text keeps 4.5:1 (7:1 with Increase Contrast), as Fluid artwork holds its own; never
// less than the least, and more under the lyrics. Over it, the shade Fluid artwork has under the controls.
static const float kCeiling = 0.18f, kCeilingContrast = 0.09f, kUnknownLight = 0.35f;
static const float kDimLeast = 0.1f, kDimMost = 0.8f;
// The dim lies only where text does, as the Music app's does: a band at the top under the status bar and header, and
// from above the title down, clear over the cover between (issue #101: over the whole clip it took up to four fifths of
// its light). The top band is whole to this share of the view, gone kDimFade points below it; the bottom darkens from
// kDimBottom down, where the shade starts.
static const CGFloat kDimTop = 0.14f, kDimFade = 48.f, kDimBottom = 0.45f;
static const float kShadeMiddle = 0.18f, kShadeBottom = 0.4f;
static const NSTimeInterval kReadyWithin = 5;

static char kReadyContext, kViewKey;

#define say(format, ...) SGLog(@"redesign player: animated: " format, ##__VA_ARGS__)

#pragma mark - a clip

// The brighter part of the clip, read once off the main thread from three small frames; `done` on the main
// queue, with kUnknownLight when none could be read.
static void readLight(NSURL *file, void (^done)(float light)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(48, 48);
    NSMutableData *lights = [NSMutableData data];
    __block NSUInteger pending = 3;
    for (NSNumber *second in @[@0, @1, @2]) {
        [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(second.doubleValue, 600) completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
            (void)generator;
            enum { kSide = 16 };
            uint8_t px[kSide * kSide * 4] = {0};
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = frame ? CGBitmapContextCreate(px, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast) : NULL;
            CGColorSpaceRelease(space);
            if (context) CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), frame);
            CGContextRelease(context);
            float read[kSide * kSide];
            for (int i = 0; context && i < kSide * kSide; i++) {
                float c[3];
                for (int k = 0; k < 3; k++) c[k] = powf(px[i * 4 + k] / 255.0f, 2.2f);
                read[i] = 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2];
            }
            @synchronized (lights) {
                if (context) [lights appendBytes:read length:sizeof read];
                if (--pending) return;
            }
            NSUInteger count = lights.length / sizeof(float);
            float *values = lights.mutableBytes;
            float light = kUnknownLight;
            if (count) {
                qsort_b(values, count, sizeof(float), ^int(const void *a, const void *b) {
                    float x = *(const float *)a, y = *(const float *)b;
                    return x < y ? -1 : x > y;
                });
                light = values[count * 3 / 4];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ done(light); });
        }];
    }
}

// A view backed by an AVPlayerLayer, so the layer tracks the view's bounds with no layout code of its own.
@interface SGRClipVideo : UIView
@end
@implementation SGRClipVideo
+ (Class)layerClass { return AVPlayerLayer.class; }
@end

// The clip's container: it keeps its subviews (the clip, and for an aspect-fit clip the blurred fill under it)
// filling its bounds, and clips their overflow.
@interface SGRClipContainer : UIView
@end
@implementation SGRClipContainer
- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *sub in self.subviews) sub.frame = self.bounds;
}
@end

// A heavy blur of the cover, drawn once, for the fill behind an aspect-fit clip. Clamped to its edges so the
// blur does not darken toward the sides, as the lock screen's Fluid clip blurs a cover (SGFluidClip.h).
static UIImage *blurredFill(UIImage *image) {
    if (!image.CGImage) return nil;
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: (id)NSNull.null}]; });
    CIImage *input = [CIImage imageWithCGImage:image.CGImage];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
    [blur setValue:@(image.size.width * 0.08) forKey:kCIInputRadiusKey];
    CGImageRef cg = [context createCGImage:blur.outputImage fromRect:input.extent];
    if (!cg) return nil;
    UIImage *result = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return result;
}

// One frame of the clip, at a modest size, read off the main thread for the blurred fill; `done` on the main
// queue, nil if none. The clip's own frame always exists and matches the cover, where the now playing artwork
// may be empty for a static cover played as a clip.
static void coverFrame(NSURL *file, void (^done)(UIImage *frame)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(320, 320);
    [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(0, 600) completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
        (void)generator;
        UIImage *image = frame ? [UIImage imageWithCGImage:frame] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(image); });
    }];
}

@interface SGRPlayerClip : NSObject
@property (nonatomic, readonly) NSURL *file;
@property (nonatomic, readonly) UIView *view;   // the clip, with a blurred fill of the cover behind it when it fits
@property (nonatomic, readonly) BOOL covers;   // its view is opaque over the whole plane (a fill clip, or a fit clip with its blurred fill)
@property (nonatomic, readonly) BOOL drawable; // its first frame can be drawn
@property (nonatomic, readonly) float light;   // negative until read
// Once, on the main queue, when its first frame can be drawn and its light has been read.
@property (nonatomic, copy) void (^ready)(SGRPlayerClip *clip);
- (instancetype)initWithFile:(NSURL *)file;
- (void)setPlaying:(BOOL)playing;
- (void)stop;
@end

@implementation SGRPlayerClip {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    SGRClipVideo *_front;   // the clip itself
    AVPlayerLayer *_video;  // _front's layer
    UIImage *_coverImage;   // a frame of the clip, for the blurred fill
    BOOL _frameTried;       // the frame has been read (or failed)
    BOOL _observing;
}

// Muted, never on AirPlay, letting the screen lock.
- (instancetype)initWithFile:(NSURL *)file {
    if (!(self = [super init])) return nil;
    _file = file;
    AVQueuePlayer *player = [AVQueuePlayer new];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _player = player;
    _view = [[SGRClipContainer alloc] init];
    _view.clipsToBounds = YES;
    _view.userInteractionEnabled = NO;
    _front = [[SGRClipVideo alloc] init];
    _video = (AVPlayerLayer *)_front.layer;
    _video.player = player;
    // Set from the video's own shape once it can be drawn (checkReady): a Canvas fills the player fullscreen,
    // Apple Music's 3:4/square cover fits whole over a blurred fill of the cover. Fill until then.
    _video.videoGravity = AVLayerVideoGravityResizeAspectFill;
    // The aspect-fit letterbox must be clear, or the layer paints its bars with an opaque (light, in a light
    // appearance) background over the blurred fill behind the clip, which is the whole point of the fill.
    _front.opaque = NO;
    _video.backgroundColor = UIColor.clearColor.CGColor;
    _covers = YES;   // a fill clip covers the plane; a fit clip only if its blurred fill is built (checkReady)
    [_view addSubview:_front];
    [_video addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:&kReadyContext];
    _observing = YES;
    _light = -1;
    __weak SGRPlayerClip *weakSelf = self;
    readLight(file, ^(float light) {
        SGRPlayerClip *clip = weakSelf;
        if (!clip) return;
        clip->_light = light;
        [clip checkReady];
    });
    coverFrame(file, ^(UIImage *frame) {
        SGRPlayerClip *clip = weakSelf;
        if (!clip) return;
        clip->_coverImage = frame;
        clip->_frameTried = YES;
        [clip checkReady];
    });
    return self;
}

- (BOOL)drawable {
    return _video.readyForDisplay;
}

- (void)checkReady {
    void (^ready)(SGRPlayerClip *) = _ready;
    if (!ready || _light < 0 || !_frameTried || !_video.readyForDisplay) return;
    _ready = nil;
    // The item's presentation size is its displayed shape, rotation already applied. A Canvas, vertical (~9:16)
    // or landscape (~16:9), fills the player fullscreen, cropping the excess. Only a roughly portrait-to-square
    // clip (Apple Music's 3:4 or square cover) fits whole with no zoom, and then a blurred fill of the cover is
    // drawn behind it so the bars read as a soft continuation of it. The fill it was made with stands until known.
    CGSize size = _player.currentItem.presentationSize;
    CGFloat ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 0;
    if (ratio >= 0.65 && ratio <= 1.2) {
        _video.videoGravity = AVLayerVideoGravityResizeAspect;
        // If no fill could be built at all (no frame and no artwork), leave the field uncovered so its Fluid
        // artwork fills the bars instead of the plain base.
        _covers = [self addBlurredFill];
    }
    ready(self);
}

// A blurred, aspect-fill copy of the clip behind the fitted clip, so the bars are a soft continuation of it
// rather than plain background. A still of a clip frame (the now playing artwork only as a fallback, since it is
// empty for a static cover played as a clip), not a second video: heavily blurred, its motion would not read.
- (BOOL)addBlurredFill {
    BOOL fromClip = _coverImage != nil;
    UIImage *fill = blurredFill(_coverImage ?: SGRNowPlayingArtwork(NULL, NULL));
    say(@"blurred fill %@%@", fill ? @"built from " : @"not built: no source",
        fill ? (fromClip ? @"the clip frame" : @"the now playing artwork") : @"");
    if (!fill) return NO;
    UIImageView *back = [[UIImageView alloc] initWithImage:fill];
    back.contentMode = UIViewContentModeScaleAspectFill;
    back.clipsToBounds = YES;
    [_view insertSubview:back atIndex:0];
    [_view setNeedsLayout];
    return YES;
}

- (void)dealloc {
    [self stop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak SGRPlayerClip *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf checkReady]; });
}

- (void)setPlaying:(BOOL)playing {
    if (playing && _player.rate == 0) [_player play];
    else if (!playing && _player.rate != 0) [_player pause];
}

- (void)stop {
    if (_observing) [_video removeObserver:self forKeyPath:@"readyForDisplay" context:&kReadyContext];
    _observing = NO;
    _ready = nil;
    [_player pause];
    [_looper disableLooping];
    [_view removeFromSuperview];
}

@end

#pragma mark - the view

// The clip over the field, with the dim and the shade that keep the player's text readable on it. The
// view fades as a whole between the field and a clip; one clip replacing another fades in over it.
@interface SGRPlayerAnimatedView : UIView
@property (nonatomic, readonly) SGRPlayerClip *clip;   // shown or coming in
@property (nonatomic, readonly) BOOL covers;           // a clip lies opaque over the whole field
@property (nonatomic, readonly) BOOL shown;            // on screen or fading in
@property (nonatomic, readonly) CFTimeInterval fadeEnds;
@property (nonatomic, copy) void (^coversChanged)(BOOL covers);
@property (nonatomic, copy) void (^shownChanged)(BOOL shown, NSTimeInterval duration);
@property (nonatomic, copy) void (^windowChanged)(void);
@property (nonatomic, copy) void (^neverReady)(SGRPlayerClip *clip);
- (void)showClip:(SGRPlayerClip *)clip;
- (void)clear:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
@end

@implementation SGRPlayerAnimatedView {
    UIView *_clips;
    CAGradientLayer *_dim;
    CAGradientLayer *_shade;
    NSMutableArray<SGRPlayerClip *> *_leaving;   // under the one coming in until it is in
    BOOL _playing;
    float _light;   // the shown clip's
    NSUInteger _generation;
}

// Blending black at `dim` over sRGB scales linear light by about (1 - dim)^2.2.
static float dimFor(float light) {
    float ceiling = SGRIncreaseContrast() ? kCeilingContrast : kCeiling;
    float need = light > ceiling ? 1 - powf(ceiling / light, 1 / 2.2f) : 0;
    return MIN(kDimMost, MAX(kDimLeast, need));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.opacity = 0;
    _leaving = [NSMutableArray array];
    NSNull *off = NSNull.null;
    NSDictionary *still = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off, @"sublayers": off};
    NSDictionary *stillGradient = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off, @"sublayers": off,
                                    @"colors": off, @"locations": off};
    _clips = [UIView new];
    _clips.userInteractionEnabled = NO;
    [self addSubview:_clips];
    _dim = [CAGradientLayer layer];
    _dim.actions = stillGradient;
    // Black at the top and from above the title down, clear over the cover between; its opacity scales all of it with how
    // bright the clip is (dimFor). Locations in layoutSubviews, where the view's height gives the top band's fade.
    UIColor *dimBlack = UIColor.blackColor;
    id dimSolid = (id)dimBlack.CGColor, dimClear = (id)[dimBlack colorWithAlphaComponent:0].CGColor;
    _dim.colors = @[dimSolid, dimSolid, dimClear, dimClear, dimSolid];
    _light = kUnknownLight;
    _dim.opacity = dimFor(_light);
    [self.layer addSublayer:_dim];
    _shade = [CAGradientLayer layer];
    _shade.actions = still;
    UIColor *black = UIColor.blackColor;
    _shade.colors = @[(id)[black colorWithAlphaComponent:0].CGColor, (id)[black colorWithAlphaComponent:kShadeMiddle].CGColor,
                      (id)[black colorWithAlphaComponent:kShadeBottom].CGColor];
    _shade.locations = @[@0.45, @0.75, @1];
    [self.layer addSublayer:_shade];
    return self;
}

- (void)dealloc {
    [_clip stop];
    for (SGRPlayerClip *clip in _leaving) [clip stop];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _clips.frame = bounds;
    _dim.frame = bounds;
    // The top band is whole to kDimTop of the view and gone kDimFade points below it; the bottom goes dark from kDimBottom.
    CGFloat height = MAX(1, bounds.size.height);
    CGFloat topFade = MIN(kDimTop + kDimFade / height, kDimBottom);
    _dim.locations = @[@0, @(kDimTop), @(topFade), @(kDimBottom), @1];
    _shade.frame = bounds;
    _clip.view.frame = bounds;
    for (SGRPlayerClip *clip in _leaving) clip.view.frame = bounds;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (_windowChanged) _windowChanged();
}

- (void)setCovers:(BOOL)covers {
    if (covers == _covers) return;
    _covers = covers;
    if (_coversChanged) _coversChanged(covers);
}

static float shownOpacity(CALayer *layer) {
    return ((CALayer *)layer.presentationLayer ?: layer).opacity;
}

// From wherever it is now, so a fade caught halfway turns back without a jump.
static void fade(CALayer *layer, float to, NSTimeInterval duration) {
    float from = shownOpacity(layer);
    layer.opacity = to;
    if (duration <= 0 || fabsf(from - to) < 0.001f) {
        [layer removeAnimationForKey:@"fade"];
        return;
    }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(from);
    animation.toValue = @(to);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:animation forKey:@"fade"];
}

// The view's own fade, which the covers keep in step with.
- (void)fadeTo:(BOOL)shown duration:(NSTimeInterval)duration {
    float to = shown ? 1 : 0;
    if (fabsf(shownOpacity(self.layer) - to) < 0.001f) duration = 0;
    fade(self.layer, to, duration);
    _fadeEnds = CACurrentMediaTime() + duration;
    if (shown == _shown) return;
    _shown = shown;
    if (_shownChanged) _shownChanged(shown, duration);
}

- (void)showClip:(SGRPlayerClip *)clip {
    if (!clip || clip == _clip) return;
    NSUInteger generation = ++_generation;
    if (_clip) [_leaving addObject:_clip];
    _clip = clip;
    clip.view.frame = self.bounds;
    clip.view.layer.opacity = 0;
    [_clips addSubview:clip.view];
    [clip setPlaying:_playing];
    __weak SGRPlayerAnimatedView *weakSelf = self;
    clip.ready = ^(SGRPlayerClip *ready) { [weakSelf fadeIn:ready generation:generation]; };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReadyWithin * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerAnimatedView *view = weakSelf;
        // A clip that has faded in was drawn; one still waiting while the app is away (Notification Center) is
        // not broken, it draws once the app is back.
        if (!view || view.clip != clip || !clip.ready || clip.drawable) return;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (view.neverReady) view.neverReady(clip);
    });
}

- (void)dropLeaving {
    for (SGRPlayerClip *clip in _leaving) [clip stop];
    [_leaving removeAllObjects];
}

- (void)fadeIn:(SGRPlayerClip *)clip generation:(NSUInteger)generation {
    if (clip != _clip || generation != _generation) return;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (!view || generation != view->_generation) return;
        [view dropLeaving];
        // The clip's view covers the plane (a fill clip, or a fit cover with its blurred fill), so the Fluid
        // field underneath is taken away; a fit cover with no fill built leaves it to show through the bars.
        [view setCovers:clip.covers];
    }];
    _light = clip.light;
    fade(_dim, dimFor(_light), shownOpacity(self.layer) > 0.01f ? kFadeIn : 0);
    say(@"%@ fades in, its light %.2f dimmed by %.2f", clip.file.lastPathComponent, _light, dimFor(_light));
    // Over a clip still on screen the new one fades in on top of it; over the field the whole view does.
    if (_leaving.count && shownOpacity(self.layer) > 0.01f) {
        clip.view.layer.opacity = 0;
        fade(clip.view.layer, 1, kFadeIn);
    } else {
        clip.view.layer.opacity = 1;
        [self dropLeaving];
    }
    [self fadeTo:YES duration:kFadeIn];
    [CATransaction commit];
}

- (void)clear:(BOOL)animated {
    if (!_clip && !_leaving.count && shownOpacity(self.layer) < 0.001f) return;
    NSUInteger generation = ++_generation;
    [self setCovers:NO];
    if (_clip) [_leaving addObject:_clip];
    _clip.ready = nil;
    _clip = nil;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (view && generation == view->_generation) [view dropLeaving];
    }];
    [self fadeTo:NO duration:animated && self.window ? kFadeOut : 0];
    [CATransaction commit];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    [_clip setPlaying:playing];
    for (SGRPlayerClip *clip in _leaving) [clip setPlaying:playing];
}

@end

#pragma mark - finding the clip

// The sources are walked by Shared/AnimatedArtwork's follower, one track at a time and the next track's clip
// fetched ahead; it hands over the clip as a file on disk, or nil when no source has one.
static __weak SGRPlayerAnimatedView *sg_view;
static __weak SGRArtworkField *sg_field;
static NSString *sg_wanted;      // the playing track, once its clip is asked for
static NSURL *sg_wantedFile;     // what the follower found for it, nil for none
static SGMotionFollower *sg_follower;
static BOOL sg_walking;          // the follower has been let walk since the conditions last held
static NSHashTable *sg_videos;   // Spotify's own video views with a video on them
static BOOL sg_lyricsUp;
// Read at launch and when the choice changes, not on each of the plane's layout passes.
static BOOL sg_picked;

static void update(void);

// Why no clip may play at all right now, or nil.
static NSString *heldBack(void) {
    if (!sg_picked) return @"Fluid artwork is picked";
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) return @"Low Power Mode";
    if (SGRReduceMotion()) return @"Reduce Motion";
    if (sg_videos.allObjects.count) return @"Spotify's own video is showing";
    // Fluid artwork is the song's colours blurred: behind the lyrics it reads better than a moving picture.
    if (sg_lyricsUp) return @"the lyrics are up";
    return nil;
}

static void playOrHold(void);

static void arrived(NSString *uri, NSURL *file) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view || ![uri isEqualToString:sg_wanted]) return;
    sg_wantedFile = file;
    if (!file) {
        if (view.clip) say(@"fades to Fluid artwork, no clip for %@", uri);
        [view clear:YES];
        say(@"no clip for %@", uri);
    } else if ([view.clip.file isEqual:file]) {
        say(@"%@ goes on with the same clip", uri);
    } else {
        say(@"clip for %@, %@", uri, view.clip ? @"crosses over from the last clip" : @"fades in over Fluid artwork");
        [view showClip:[[SGRPlayerClip alloc] initWithFile:file]];
        playOrHold();
    }
}

// A walk begins for a track: only with the player on screen and nothing holding the clip back; the last clip
// goes while the new one is found.
static BOOL walkBegins(NSString *uri, SPTPlayerState *state) {
    SGRPlayerAnimatedView *view = sg_view;
    if (heldBack() || !view.window || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
        sg_wanted = nil;
        return NO;
    }
    sg_wanted = uri;
    sg_wantedFile = nil;
    if (view.clip) {
        say(@"fades to Fluid artwork while %@'s clip is found", uri);
        [view clear:YES];
    }
    return YES;
}

#pragma mark - playing and holding

static void playOrHold(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    NSString *why = nil;
    if (!view.window) why = @"the player is not on screen";
    else if (state != UIApplicationStateActive) why = @"the app is not in front";
    else if (SGRPlayerIsTransitioning()) why = @"the player opens or closes";
    else if (SGPlayerState().isPaused) why = @"the song is paused";
    [view setPlaying:!why];
    static NSString *said;
    NSString *now = why ?: @"plays";
    if (!view.clip || [now isEqualToString:said]) return;
    said = now;
    say(@"%@", why ? [@"holds its frame, " stringByAppendingString:why] : @"plays");
}

static void update(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    NSString *held = heldBack();
    BOOL walks = !held && view.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    if (held) {
        if (view.clip) say(@"fades to Fluid artwork: %@", held);
        [view clear:YES];
        sg_wanted = nil;
    }
    if (walks && !sg_walking) {
        sg_walking = YES;
        [sg_follower restart];
    } else if (!walks) {
        sg_walking = NO;
    }
    playOrHold();
}

static void covered(BOOL covers) {
    SGRArtworkField *field = sg_field;
    field.covered = covers;
    say(@"Fluid artwork %@", covers ? @"stops under the clip" : @"draws again");
}

// The cover goes as a clip fades in and comes back as it fades out, over the same time (PlayerArtwork.x).
static void shownChanged(BOOL shown, NSTimeInterval duration) {
    say(@"the cover %@ over %.2f s", shown ? @"goes as the clip fades in" : @"comes back as the clip fades out", duration);
    SGRPlayerCoversFollowClip(duration);
}

BOOL SGRPlayerAnimatedShowing(CGFloat *shown, NSTimeInterval *left) {
    SGRPlayerAnimatedView *view = sg_view;
    if (shown) *shown = view ? shownOpacity(view.layer) : 0;
    if (left) *left = view ? MAX(0, view.fadeEnds - CACurrentMediaTime()) : 0;
    return view.shown;
}

UIView *SGRPlayerAnimatedViewIn(UIView *plane, SGRArtworkField *field) {
    SGRPlayerAnimatedView *view = objc_getAssociatedObject(plane, &kViewKey);
    if (!sg_picked) {
        // Kept until it has faded out to the field.
        if (view && !view.clip && shownOpacity(view.layer) < 0.01f) {
            [view removeFromSuperview];
            objc_setAssociatedObject(plane, &kViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            field.covered = NO;
            return nil;
        }
        return view;
    }
    if (!view) {
        view = [[SGRPlayerAnimatedView alloc] initWithFrame:plane.bounds];
        objc_setAssociatedObject(plane, &kViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.coversChanged = ^(BOOL covers) { covered(covers); };
        view.shownChanged = ^(BOOL shown, NSTimeInterval duration) { shownChanged(shown, duration); };
        view.windowChanged = ^{ update(); };
        view.neverReady = ^(SGRPlayerClip *clip) {
            say(@"%@ could not be drawn, Fluid artwork stays", clip.file.lastPathComponent);
            if ([sg_wantedFile isEqual:clip.file]) sg_wantedFile = nil;
            [sg_view clear:YES];
        };
        say(@"view made in the background plane");
    }
    sg_field = field;
    if (field.covered != view.covers) field.covered = view.covers;
    // Another player's plane: the covers follow its clip instead.
    if (sg_view != view) {
        sg_view = view;
        SGRPlayerCoversFollowClip(0);
    }
    return view;
}

void SGRPlayerAnimatedFollowLyrics(BOOL open, BOOL animated) {
    sg_lyricsUp = open;
    update();
}

#pragma mark - the player

@interface SGRPlayerAnimatedWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerAnimatedWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    SGRPlayerAnimatedView *view = sg_view;
    // Out of sight nothing is looked up, and the last track's clip must not greet the player as it opens.
    if (uri && ![uri isEqualToString:_track]) {
        _track = uri;
        if (!view.window || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
            [view clear:NO];
            sg_wanted = nil;
        }
    }
    update();
}

@end

static SGRPlayerAnimatedWatcher *sg_watcher;

// Switch to video puts a music video where the cover is, on one of these; the clip goes while it is on.
static void spotifyVideo(id owner, BOOL attached) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_videos) sg_videos = [NSHashTable weakObjectsHashTable];
        BOOL was = sg_videos.allObjects.count > 0;
        if (attached) [sg_videos addObject:owner];
        else [sg_videos removeObject:owner];
        BOOL now = sg_videos.allObjects.count > 0;
        if (now == was) return;
        say(@"Spotify's own video %@ (%@)", now ? @"shows" : @"is gone", NSStringFromClass([owner class]));
        update();
    });
}

%hook _TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC22NowPlaying_ElementsKit14VideoElementUI
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) { return walkBegins(uri, state); }
                                                    found:^(NSString *uri, NSURL *file) { arrived(uri, file); }];
    sg_watcher = [SGRPlayerAnimatedWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    sg_picked = SGRPlayerBackground() == SGRPlayerBackgroundAnimated;
    [center addObserverForName:SGRPlayerBackgroundDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        sg_picked = SGRPlayerBackground() == SGRPlayerBackgroundAnimated;
        say(@"%@ picked", sg_picked ? @"Animated artwork" : @"Fluid artwork");
        update();
    }];
    // The main queue, since the power state is reported off it.
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { update(); }];
    }
    SGRObservePlayerTransition(sg_watcher, ^(id owner) { playOrHold(); }, ^(id owner) { playOrHold(); });
    SGRequireClasses(@[
        @"_TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel",
        @"_TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation",
        @"_TtC22NowPlaying_ElementsKit14VideoElementUI",
    ]);
}
