#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Lossless/SGLossless.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Home/Home.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Gestures/Gestures.h"

NSString *const SGRedesignedUIInfo = @"The newest version of Sigma, leaning towards Apple Music's style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.";

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
    if (!SGRedesignTested()) SGSetEnabled(SGKeyRedesignUntested, on);
}

NSString *SGRedesignUntestedWarning(void) {
    return [NSString stringWithFormat:@"The redesign is made for iOS 26 and has not been tested on iOS %@ at all. Expect bugs and freezes. If Spotify stops opening, delete and reinstall it.", UIDevice.currentDevice.systemVersion];
}

// The whole look changes hands at launch, so the switch asks for the restart straight away rather than
// leaving Spotify half in the old look.
static void offerRestart(BOOL on) {
    NSString *restart = on ? @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it." : @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it.";
    BOOL untested = on && !SGRedesignTested();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:untested ? @"Not tested on this iOS" : @"Restart Spotify"
        message:untested ? [NSString stringWithFormat:@"%@\n\n%@", SGRedesignUntestedWarning(), restart] : restart
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModSection *SGAppearanceSection(void) {
    SGModRow *redesign = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObject:SGWithSymbol(redesign, @"sparkles")];
    [rows addObjectsFromArray:SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows()];
    if (SGRedesignedUIStored()) [rows addObject:SGRHomeTopPicksRow()];
    // One font for the whole app, under either look.
    [rows addObjectsFromArray:SGAppFontRows()];
    return SGNotedSection(@"Appearance", rows, @"Changes apply after you restart Spotify.");
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// Pronunciation, translation, word sweeping and line meanings exist only in the redesign's lyrics.
UIViewController *SGLyricsSettingsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGLyricsSourcesSection(redesigned)];
    [sections addObject:SGNotedSection(@"Timing", @[SGLyricsDelayRow()],
        @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. Applies at once.")];
    if (redesigned) {
        [sections addObject:SGSection(@"Display", @[SGLyricsWordTimingRow(), SGRLyricsTextSizesRow(), SGLyricsTranslationLanguageRow(), SGLyricsMeaningsRow(),
            SGSwitchRow(@"Landscape lyrics", @"Turn the phone with the lyrics open", SGRKeyLyricsLandscape)])];
    }
    [sections addObject:SGSection(nil, more)];
    return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:SGRestartNote sections:sections footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    BOOL native = !SGRedesignedUIStored();

    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    if (native) {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing bar", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"Queue & devices", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward")];
    }
    // Double taps over the artwork, under either look.
    [pages addObject:SGWithSymbol(SGPageRow(@"Gestures", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap")];
    [pages addObject:SGWithSymbol(SGPageRow(@"Lock screen widget", ^UIViewController *{ return SGLockScreenWidgetPage(); }), @"lock")];
    [sections addObject:SGSection(nil, pages)];
    [sections addObjectsFromArray:native ? SGNativePlayerScreenSections() : SGRNowPlayingSections()];
    // Vibrations hook Spotify's own controls and its audio, so they answer under either look.
    [sections addObject:SGSection(nil, @[SGWithSymbol(SGPageRow(@"Vibrations", ^UIViewController *{ return SGVibrationsSettingsPage(); }), @"iphone.radiowaves.left.and.right")])];
    // Switch to video is the same chip of Spotify's player under either look.
    [sections addObject:SGSection(native ? nil : @"Hide on the player", @[
        SGHideRow(@"Switch to video", @"The chip over the title of a song with a music video", SGKeyHideVideoSwitch),
    ])];
    [sections addObject:SGNotedSection(@"Lossless", @[
        SGOptionRow(@"Lossless files", @"Your own FLACs in place of Spotify's stream", SGKeyLossless),
    ], @"Put FLAC or ALAC files in Files › Spotify › Lossless. A file plays when its title and length match the song "
       @"and its sound matches what Spotify plays, from about 4 s after the song starts or you seek. Spotify still "
       @"streams its own copy, at its lowest quality while the next song has a file. Karaoke and speeds other than "
       @"1x keep Spotify's sound. Applies after you restart Spotify.")];

    return [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:sections footer:nil];
}
