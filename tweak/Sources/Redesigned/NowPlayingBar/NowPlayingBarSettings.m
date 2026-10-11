// The redesign's rows on the Player page (App/Pages.m puts them there): the bar and what moves behind
// the player.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

NSArray<SGModSection *> *SGRNowPlayingSections(void) {
    return [@[
        SGSection(nil, @[
            SGHideRow(@"Hide the device button", nil, SGRHideBarConnect),
        ]),
        SGNotedSection(@"Controls", @[SGSwitchRow(@"Volume", nil, SGRKeyPlayerVolume)],
                       @"Volume puts a slider under the controls for this iPhone, or the speaker's while Spotify plays on another device."),
    ] arrayByAddingObjectsFromArray:SGRPlayerBackgroundSections()];
}
