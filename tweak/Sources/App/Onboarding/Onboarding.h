// Onboarding: a welcome page over Home the first time this build runs, in glass: a pick between
// the redesign (offered first) and Spotify's own look, and a line on holding Home for Mod Settings.
// The look is picked at launch, so a changed pick ends the welcome in a restart. The Mod page
// offers it again.
#import <UIKit/UIKit.h>

#define SGKeyOnboardingSeen @"spotifyglass.onboarding.seen"
// The version whose What's new was last shown, or skipped because the tour came first.
#define SGKeyWhatsNewSeen @"spotifyglass.whatsnew.seen"

// Presents the tour over the top of the app; does nothing while it is already up.
void SGShowOnboarding(void);
// The tour or What's new holds the screen; other sheets wait for it (App/About).
BOOL SGOnboardingShowing(void);

// WhatsNew.m: this build's section of CHANGELOG.md, read through App/About/ChangeNotes.m's parser; empty for a
// build with no section of its own, which then has no sheet and no row.
@class SGUpdateChange;
NSArray<SGUpdateChange *> *SGWhatsNewChanges(void);
void SGShowWhatsNew(void);
BOOL SGWhatsNewShowing(void);

// The tour's prominent glass button, also What's new's Continue.
UIButton *SGOnboardingButton(NSString *title);
