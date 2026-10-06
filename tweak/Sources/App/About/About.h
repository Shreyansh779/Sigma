// About: the Mod page and its warnings.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"


// Whether the now playing card on the lock screen can open this build. It depends on the signature,
// not on the mod: iOS launches by the App ID of the application-identifier entitlement, so a build
// whose bundle id is not that App ID cannot be opened from the card. Signing.m says so once.
NSString *SGSigningAppIdentifier(void);      // App ID without the team prefix, nil if unreadable
BOOL SGSigningOpensFromLockScreen(void);     // YES when unreadable, so a build that works stays quiet
SGModRow *SGSigningWarningRow(void);          // nil while the signature is sound
void SGCheckSigningOnce(void);
void SGShowSigningFixIfPending(void);   // the sheet the tour held back, if any

// Compatibility.m: a Spotify other than SGSupportedSpotifyVersion, or EeveeSpotify injected alongside.
// Each gets an alert once and a red row at the top of Mod Settings.
NSArray<SGModRow *> *SGCompatibilityWarningRows(void);   // empty when neither
void SGCheckCompatibilityOnce(void);

// AppIcon.m: the row that opens the list of app icons, nil in a build without them (scripts/app-icons.sh).
SGModRow *SGAppIconRow(void);

UIViewController *SGAboutPage(void);   // the Mod page
