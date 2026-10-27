// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(@"Apple Music style", @"Between two tabs as a page scrolls down", SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    return @[
        minimize,
        SGHideRow(@"Hide the device button", @"On the full now playing bar", SGRHideBarConnect),
        // The redesign's own switch; the flag it forces is Spotify's, and the native look's save button reads the same one.
        SGSwitchRow(@"Hide the like button", @"On the full now playing bar", SGRKeyBarHideLike),
    ];
}
