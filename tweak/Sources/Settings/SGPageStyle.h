// Spotify's own list look, for every page of the mod's: a 13pt white title over an 11pt grey
// subtitle on #121212, 38pt uppercase section headers, green switches.
#import <UIKit/UIKit.h>

UIColor *SGGrey(void);
UIColor *SGGreen(void);
UIColor *SGRed(void);
UIColor *SGPageBackground(void);
UIColor *SGCardBackground(void);
UIColor *SGOnAccent(void);   // black or white text on the accent
UIColor *SGAccentMark(void); // a visible accent mark on a dark card
// Both grow through the accessibility sizes with no cap. A control beside a row's title, or text inside a
// drawing of fixed size, caps its copy so the title keeps its room.
UIFont *SGCappedFont(UIFont *font, CGFloat largest);
BOOL SGAccessibilityTextSize(void);   // an accessibility size, where a row's value goes under its title
// A slider row's text, laid out by hand: the title with its value at the trailing edge, or at the accessibility
// sizes the title wrapped across the row with the value under it, then the subtitle when it has one. The
// layout returns the y under the text; the height is the same text measured at the same width.
CGFloat SGSliderTextHeight(NSString *title, NSString *subtitle, CGFloat width);
CGFloat SGLayOutSliderText(UILabel *title, UILabel *value, UILabel *subtitle, CGFloat x, CGFloat y, CGFloat width);
// The chevron of a row that opens a page, in the tertiary label's gray.
UIImageView *SGChevronView(void);
UIFont *SGTitleFont(void);
UIFont *SGSubtitleFont(void);
// Takes the 13pt and 11pt fonts off Spotify's own settings list, once, so the pages match it.
void SGAdoptFonts(UIView *list, UIView *exclude);

UIImageView *SGSymbolView(NSString *name, CGFloat size, UIImageSymbolWeight weight, CGFloat box);
// A symbol on a rounded grey square, the leading icon of a row that opens a page.
UIImage *SGTileImage(NSString *symbol);
// A grey note in a wrapper view, for a table header or footer; SGFitNote sizes it to its text.
UIView *SGNote(NSString *text);
void SGFitNote(UITableView *table, UIView *wrapper, CGFloat top, CGFloat bottom);
// The now playing bar and the tab bar float over the content, so a page insets itself under them.
void SGInsetForBars(UITableView *table);

extern const CGFloat SGSectionHeaderHeight;
extern const CGFloat SGSectionGap;   // above a section with no header, so its card does not touch the one before
void SGFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbolName);
UIView *SGSectionHeader(UITableView *table, NSString *title);
UIView *SGSectionFooter(UITableView *table, NSString *text);
CGFloat SGSectionFooterHeight(UITableView *table, NSString *text);
// The same with a link after the text, in the accent colour and read out by its host; a tap on the
// footer opens it. Measured by SGSectionFooterHeight with SGLinkedFooterText.
UIView *SGLinkedSectionFooter(UITableView *table, NSString *text, NSString *url);
NSString *SGLinkedFooterText(NSString *text, NSString *url);
UITableViewCell *SGDequeueCell(UITableView *table, NSString *identifier);

void SGOpenURL(NSString *url);
extern NSString *const SGDiscordURL;
// The Spotify build the mod is made for (AGENTS.md lists what else follows it on a bump).
extern NSString *const SGSupportedSpotifyVersion;
// What else it is run and checked on, and what ran cleanly in a short test only. A version in neither list
// gets the "isn't supported" alert (App/About/Compatibility.m).
extern NSArray<NSString *> *SGSupportedSpotifyVersions(void);
extern NSArray<NSString *> *SGLikelyWorksSpotifyVersions(void);
// The controller on top of the key window, through whatever is presented over it.
UIViewController *SGTopController(void);
