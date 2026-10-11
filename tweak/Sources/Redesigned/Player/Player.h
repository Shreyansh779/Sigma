// The player redesign (screen key "player"): Spotify's full screen player kept, with its controller,
// units, controls and card list, and restyled from the Kit. Every control stays Spotify's own, so its
// action, state and accessibility do too; the redesign adds the artwork field behind it, glass behind
// the header buttons, bare glyphs for previous, play and next, a lyrics glyph in the footer, and one
// screen with nothing under it: every card is collapsed and the player does not scroll. The lyrics
// come to the player itself, the way the Music app shows them, when the lyrics glyph is tapped, and
// have it to themselves while they play untouched, until a touch brings the controls back.
//
//     PlayerField.x      the switch's flags and rows, the field in the background plane, the cover it reads
//     PlayerAnimated.x   Animated artwork: the Canvas or Apple Music's cover looping over the field
//     PlayerVisualiser.m the Visualizer background: a calm spectrum of the song in the cover's colours, read
//                        through SGRSpectrum.m from the audio effects' tap on Spotify's output
//     PlayerCoverAccent.x  Follow the cover: the like, shuffle and repeat painted in the cover's colour
//     PlayerBackgroundSettings.m  what moves behind the player, and Fluid artwork's sliders under a preview
//     PlayerArtwork.x    the cover's corners, shadow and paused shrink, the lyric preview under it hidden,
//                        and every cover gone while an Animated artwork clip shows
//     PlayerHeader.x     glass behind the close and more buttons
//     PlayerControls.x   previous, play and next as bare glyphs, monospaced times
//     PlayerFooter.x     share gone, lyrics, Connect and queue as one row of three glyphs
//     PlayerCards.x      every card under the player collapsed, so the list closes up
//     PlayerScroll.x     the list held at its top, so the player is one screen and cannot be scrolled up
//     PlayerLyrics.x     the lyrics in the player: the cover as a thumbnail, the title up beside it,
//                        and after a few seconds untouched the lines alone on the whole player
//     PlayerMorph.x      the open and close grown out of the now playing bar's card, the cover flown
//     PlayerMenu.x       the ⋯ opening a menu the way the Music app draws one (SGRPlayerMenu.h), over
//                        Spotify's own sheet, which it reads its rows from and keeps out of sight
//
// A Spotify Free account with pick and shuffle gets the player in another mode (NowPlayingReinventFreeMode),
// whose header, information, duration, controls and footer units are classes of their own holding the
// same elements, so each hook on one of those units hooks its Free counterpart too.
//
// Speed and pitch, once the redesign's own, are Shared/Player/SpeedPitch.h's; PlayerHeader.x still hands
// the more button over, so a menu opened from it is taken for the player's.
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRWarp.h"

@class SGRArtworkField, SGModSection;

#pragma mark - the background (PlayerBackgroundSettings.m)

// What moves behind the player, picked on Mod Settings' Player page (Redesigned/NowPlayingBar/
// NowPlayingBarSettings.m), stored as the index. Every value of the choice it replaced (Still artwork,
// Colour flow, Fluid artwork) and of the Moving background switch before that reads as Fluid artwork.
#define SGRKeyPlayerBackground @"spotifyglass.redesign.player.backdrop"
#define SGRKeyPlayerBackgroundWas @"spotifyglass.redesign.player.background"
#define SGRKeyPlayerMotionWas @"spotifyglass.redesign.player.movingBackground"
typedef NS_ENUM(NSInteger, SGRPlayerBackground) {
    SGRPlayerBackgroundFluid,      // the artwork itself warped (SGRWarp.h)
    SGRPlayerBackgroundAnimated,   // a clip over Fluid artwork, where the track has one (PlayerAnimated.x)
    SGRPlayerBackgroundVisualiser, // a spectrum of the song over Fluid held still (PlayerVisualiser.m)
};
SGRPlayerBackground SGRPlayerBackgroundStyle(void);
// Posted when the choice changes, so the player follows without a restart.
extern NSNotificationName const SGRPlayerBackgroundDidChangeNotification;
// Fluid artwork's sliders, whole numbers: speed, warp, saturation and brightness in percent, blur in passes.
#define SGRKeyFluidSpeed @"spotifyglass.redesign.player.fluid.speed"
#define SGRKeyFluidWarp @"spotifyglass.redesign.player.fluid.warp"
#define SGRKeyFluidBlur @"spotifyglass.redesign.player.fluid.blur"
#define SGRKeyFluidSaturation @"spotifyglass.redesign.player.fluid.saturation"
#define SGRKeyFluidBrightness @"spotifyglass.redesign.player.fluid.brightness"
SGRWarpLook SGRPlayerFluidLook(void);
// Posted as a slider moves or the page resets them, so the player's field and the preview follow at once.
extern NSNotificationName const SGRPlayerFluidLookDidChangeNotification;
// The Player page's sections for the background: the choice, then the settings of the one picked.
NSArray<SGModSection *> *SGRPlayerBackgroundSections(void);

#pragma mark - the ⋯ menu (PlayerMenu.x)

// Marks a sheet opened soon after a tap on `button`, the player's ⋯, as the one the menu takes over, and
// the button as where the menu grows from (watching it twice does nothing).
void SGRPlayerMenuWatchMoreButton(UIView *button);

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);

#pragma mark - Animated artwork (PlayerAnimated.x)

// The view the clip plays in, for PlayerField.x to keep over `field` in the background plane; nil while
// the background is Fluid artwork.
UIView *SGRPlayerAnimatedViewIn(UIView *plane, SGRArtworkField *field);
// The lyrics coming up in the player or going: a clip behind them is dimmed a little more.
void SGRPlayerAnimatedFollowLyrics(BOOL open, BOOL animated);
// Whether a clip is on screen or fading in, which takes the cover away; `shown` gets how much of the clip
// is drawn now (0 to 1) and `left` how long its fade still runs. Either may be NULL.
BOOL SGRPlayerAnimatedShowing(CGFloat *shown, NSTimeInterval *left);

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
// The cover on screen as it is drawn, its paused shrink included, in `host`'s coordinates; CGRectNull
// when no cover has laid out.
CGRect SGRPlayerCoverFrameIn(UIView *host);
// The band that cover sits in -- the room the player gives its artwork, between the header row and the
// title -- in `host`'s coordinates; CGRectNull when no cover has laid out.
CGRect SGRPlayerArtworkAreaIn(UIView *host);
// Hides the cover on screen and its shadow, or gives them back to the clip's rule, for a stand-in to fly
// in its place (PlayerMorph.x).
void SGRPlayerSetCoverHidden(BOOL hidden);
// Every cover in the list going or coming back over `duration`, as SGRPlayerAnimatedShowing now says.
void SGRPlayerCoversFollowClip(NSTimeInterval duration);

#pragma mark - the Visualizer (PlayerVisualiser.m)

// The background is the Visualizer.
BOOL SGRPlayerVisualiserShowing(void);
// Puts the hills on the field or takes them off as the background says, lays them out, and blurs them while the
// lyrics are open. Called on every layout pass of the field (PlayerField.x), when the lyrics come or go
// (PlayerFooter.x) and when the background changes; cheap when nothing changed.
void SGRPlayerVisualiserUpdate(void);
// A view of its own drawing the same hills, for the Player page's preview. It moves only in a window.
UIView *SGRPlayerVisualiserPreview(void);
// The field holds still while the song is paused, a clip covers it or the hills move over it.
void SGRPlayerHoldField(void);

#pragma mark - Follow the cover (PlayerCoverAccent.x)

// The player's lit controls painted in the cover's colour instead of the accent. Off until switched on, read at
// launch. The cover's colour (a grey one gives the accent back), and a paint of Spotify's bottom stack, which the
// footer's layout asks for.
#define SGRKeyPlayerFollowsCover @"spotifyglass.redesign.player.followsCover"
BOOL SGRPlayerFollowsCover(void);
void SGRPlayerSetCoverAccent(UIColor *cover);
void SGRPlayerPaintCover(UIView *stack);

#pragma mark - landscape lyrics (PlayerLandscape.x)

// The lyrics turn sideways with the phone onto a landscape screen of their own. On until switched off.
// Shown or put away by hand for the harness.
#define SGRKeyLyricsLandscape @"spotifyglass.redesign.lyrics.landscape"
void SGRPlayerShowLandscape(BOOL show);

#pragma mark - the volume (PlayerVolume.m)

// A volume slider under the controls, the system's: this iPhone's, or the Connect device's. On until
// switched off, read at launch. Placed by the footer's layout, between the controls (`controls`) and the
// footer row (`row`), both arranged in Spotify's bottom stack, `margin` in from each side.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.volume"
BOOL SGRPlayerVolumeOn(void);
// YES when the row shows; NO when it is off, has no controls to sit under or no room between them and the footer.
BOOL SGRPlayerPlaceVolume(UIView *stack, UIView *controls, UIView *row, CGFloat margin);
// Whether `view` is that row, which the footer's layout must not take for Spotify's controls.
BOOL SGRPlayerIsVolumeRow(UIView *view);

#pragma mark - the lyrics in the player (PlayerLyrics.x)

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the player is showing them.
BOOL SGRPlayerLyricsOpen(void);
// Shows them, or puts the cover back; does nothing when there are none to show.
void SGRPlayerToggleLyrics(void);
// Called by PlayerLyrics.x whenever either of those two changed, so the footer's lyrics glyph follows
// (PlayerFooter.x). It returns at once when nothing changed.
void SGRPlayerLyricsChanged(void);

// Alpha 0, no touches, hidden from accessibility, set again on every call: for Spotify's Swift views,
// which SGRSuppress cannot keep (PlayerControls.x).
void SGRPlayerVanish(UIView *view);
