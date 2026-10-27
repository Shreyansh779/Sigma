// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const SGRNavbarID = @"id";
NSString *const SGRNavbarTitle = @"title";
NSString *const SGRNavbarURI = @"uri";
NSString *const SGRNavbarIcon = @"icon";
NSString *const SGRNavbarIconSet = @"iconSet";
NSString *const SGRNavbarCustomIcon = @"customIcon";
NSString *const SGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.redesign.navbar.stock";
static NSString *const kNavbarSplit = @"spotifyglass.redesign.navbar.split";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

// The Encore glyph the glass bar draws for one of Spotify's own tabs, named after the label under it, so the
// bar draws its own canonical icon rather than whichever one Spotify happens to have on the item. Nil for a
// tab this does not know, which keeps Spotify's live icon.
NSString *SGRNavbarDefaultIcon(NSString *stockID) {
    static NSDictionary<NSString *, NSString *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @{
            @"home": @"home",
            @"search": @"search",
            @"your library": @"collection",
            @"library": @"collection",
            @"liked songs": @"heart",
            @"playlists": @"playlist",
            @"albums": @"album",
            @"artists": @"artist",
            @"podcasts": @"podcasts",
            @"audiobooks": @"audiobook",
            @"downloads": @"downloaded",
            @"your episodes": @"bookmark",
            @"browse": @"browse",
            @"new releases": @"star",
            @"made for you": @"user",
            @"concerts": @"events",
            @"queue": @"queue",
            @"create": @"plus",
        };
    });
    return icons[stockID.lowercaseString];
}

// Whether a tab's entry names an icon of the user's own choosing, rather than the tab's canonical one: a
// custom icon the glass bar draws in place of the default. A mod's own tab (a URI) always draws the icon it
// was given, so this is only asked of Spotify's own tabs.
BOOL SGRNavbarEntryHasCustomIcon(NSDictionary *entry) {
    if ([entry[SGRNavbarCustomIcon] boolValue] || entry[SGRNavbarIconSet] != nil) return YES;
    id iconValue = entry[SGRNavbarIcon];
    if (![iconValue isKindOfClass:NSString.class]) return NO;
    NSString *icon = iconValue;
    NSString *defaultIcon = SGRNavbarDefaultIcon(entry[SGRNavbarID]);
    if (!icon.length || [icon isEqualToString:@"star"] || [icon isEqualToString:defaultIcon]) return NO;
    NSUInteger duplicates = 0;
    for (NSDictionary *candidate in SGRNavbarLayout()) {
        id candidateIcon = candidate[SGRNavbarIcon];
        if ([candidate[SGRNavbarID] isEqual:entry[SGRNavbarID]] || candidate[SGRNavbarURI]
            || candidate[SGRNavbarCustomIcon] || candidate[SGRNavbarIconSet] != nil
            || ![candidateIcon isKindOfClass:NSString.class] || ![candidateIcon isEqualToString:icon]) continue;
        if (![icon isEqualToString:SGRNavbarDefaultIcon(candidate[SGRNavbarID])]) duplicates++;
    }
    return duplicates == 0;
}

NSArray<NSString *> *SGRNavbarSplit(void) {
    return listOfKind(kNavbarSplit, NSString.class);
}

void SGRSetNavbarSplit(NSArray<NSString *> *split) {
    [NSUserDefaults.standardUserDefaults setObject:split ?: @[] forKey:kNavbarSplit];
}

NSArray<NSString *> *SGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSURL *SGRNavbarTabURL(NSString *uri) {
    NSURL *url = SGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
