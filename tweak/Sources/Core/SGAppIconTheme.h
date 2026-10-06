// Mod > App icon > "Use the icon's colour": the accent follows the app icon picked there instead of
// Spotify's green. The icon is kept by name under a key outside "spotifyglass.", since iOS keeps the
// icon itself through a reset of the mod's settings, so the colour stays in step with it; the switch is
// an ordinary one. Read at launch by both looks' accent code and by SGGreen.
#import <Foundation/Foundation.h>

#define SGKeyAppIconTheme @"spotifyglass.appicon.theme"

// The icon's colour as 0xRRGGBB; -1 while the switch is off or the icon has none of its own (Spotify's,
// Liquid Glass and Green are Spotify's own green).
NSInteger SGAppIconThemeRGB(void);
// The list's file name of the icon in use (App/About/AppIcon.m): "Pink", "Blue"...
void SGAppIconRemember(NSString *file);
// The one remembered, nil before any: UIApplication's alternateIconName can read nil early in a launch, or
// for an app run inside another (LiveContainer), where this is what the icon was when last looked at.
NSString *SGAppIconRemembered(void);
