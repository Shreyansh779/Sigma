#import "SGAppIconTheme.h"
#import "SGPrefs.h"

static NSString *const kIconKey = @"sigma.appicon.file";

void SGAppIconRemember(NSString *file) {
    if (file) [NSUserDefaults.standardUserDefaults setObject:file forKey:kIconKey];
}

NSString *SGAppIconRemembered(void) {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIconKey];
}

NSInteger SGAppIconThemeRGB(void) {
    if (!SGHidden(SGKeyAppIconTheme)) return -1;
    NSString *file = [NSUserDefaults.standardUserDefaults stringForKey:kIconKey];
    // The colours the icons are drawn with (icons/<Name>.icon).
    static NSDictionary<NSString *, NSNumber *> *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @{@"White": @0xFFFFFF, @"Pink": @0xF573A0, @"Blue": @0x509BF5, @"Purple": @0xAF87F0,
                   @"Orange": @0xFF6437, @"Lime": @0xCDF564};
    });
    NSNumber *rgb = file ? colors[file] : nil;
    return rgb ? rgb.integerValue : -1;
}
