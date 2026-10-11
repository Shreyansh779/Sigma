// A release's changelog as lines: Release Please writes "### Features" over a line per commit, each ending in a
// link to it, and the What's new sheet (App/Onboarding/WhatsNew.m) shows this build's section of CHANGELOG.md
// the same way.
#import "Core/SGCore.h"
#import "About.h"

@implementation SGUpdateChange
@end

// "[the text](https://…)" is left as its text, and what release-please writes around a scope --
// "**player:** …" -- loses its stars. Nothing else in a body of its is markup.
static NSString *plainText(NSString *markdown) {
    static NSRegularExpression *link;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]*)\\]\\([^)]*\\)" options:0 error:NULL];
    });
    NSString *text = [link stringByReplacingMatchesInString:markdown options:0
                                                      range:NSMakeRange(0, markdown.length) withTemplate:@"$1"];
    text = [text stringByReplacingOccurrencesOfString:@"**" withString:@""];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// The commit a line ends with -- " ([4b63f35](https://github.com/…/commit/4b63f35…))" -- taken off the
// text and kept as the line's link. A line written by hand has none and keeps all of itself.
static NSString *takeCommitURL(NSString **line) {
    static NSRegularExpression *trailer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        trailer = [NSRegularExpression regularExpressionWithPattern:@"\\s*\\(\\[[0-9a-f]{6,}\\]\\(([^)]+)\\)\\)\\s*$" options:0 error:NULL];
    });
    NSString *text = *line;
    NSTextCheckingResult *match = [trailer firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    *line = [text substringToIndex:match.range.location];
    return [text substringWithRange:[match rangeAtIndex:1]];
}

// A release body into its lines: "### Features" names what follows, "* …" is a line of it, and a
// line that wraps onto the next one is joined back together. Anything else -- the "## [0.19.0](…)"
// heading release-please leads with, blank lines -- is dropped, the version being known already.
NSArray<SGUpdateChange *> *SGUpdateChangesIn(NSString *body) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    NSString *kind = @"Changes";
    SGUpdateChange *open = nil;
    for (NSString *raw in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"###"]) {
            kind = plainText([line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]]);
            open = nil;
        } else if ([line hasPrefix:@"* "] || [line hasPrefix:@"- "]) {
            NSString *text = [line substringFromIndex:2];
            NSString *url = takeCommitURL(&text);
            text = plainText(text);
            if (!text.length) { open = nil; continue; }
            open = [SGUpdateChange new];
            open.kind = kind;
            open.text = text;
            open.url = url;
            [changes addObject:open];
        } else if (line.length && ![line hasPrefix:@"#"] && open) {
            // A line too long for one, wrapped by whoever edited the release by hand.
            NSString *text = line;
            NSString *url = takeCommitURL(&text);
            open.text = [open.text stringByAppendingFormat:@" %@", plainText(text)];
            if (url) open.url = url;
        } else {
            open = nil;
        }
    }
    return changes;
}
