// Player redesign: nothing is kept under the player. Every card (about the artist, videos, SongDNA,
// events, explore, credits, merch, the lyrics card, anything Spotify adds later) reports no height, so
// the list closes up around it and the player is one screen; PlayerScroll.x closes off the gaps the
// list leaves between them, and the lyrics come to the player itself (PlayerLyrics.x) instead of
// waiting on a card below it.
//
// A block on everything rather than a list of what to drop: the server decides which cards a track
// gets, and a new kind should not turn up under a redesigned player. The collapse is the one
// Native/Player/PlayerDeclutter.x has shipped.
//
// Tree (trees/clean/player/01.txt:385, lyrics/01.txt:996-999): every card is an Element_List.CollectionViewCell
// whose first subview is an ElementContentView naming NowPlaying_ScrollAPI, then an ElementView, then
// the card's own root: CreatorBiographyCardLayout, song-dna-npv-card, Lyrics_CardElementImpl.CardView
// id=lyrics-card-view and so on (all ten player snapshots). The cells of lists inside a card
// (WatchFeed's) name WatchFeed_ComponentAPI instead, so they are left to their card.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

// Whether the cell's content is the player's card list, remembered per content class.
static BOOL isPlayerCard(UIView *content) {
    static NSMutableSet<Class> *yes, *no;
    if (!yes) {
        yes = [NSMutableSet set];
        no = [NSMutableSet set];
    }
    Class cls = object_getClass(content);
    if (!cls || [no containsObject:cls]) return NO;
    if ([yes containsObject:cls]) return YES;
    BOOL player = [NSStringFromClass(cls) containsString:@"NowPlaying_ScrollAPI"];
    [(player ? yes : no) addObject:cls];
    return player;
}

static char kCollapsedKey;

// A card's cell is 0 tall, but what it holds keeps the height it measured at, hidden and cut off by the cell. Squeezed
// to 0 with the cell, Spotify's card content breaks its required constraints on every layout pass, which held the main
// thread for a second or more while the first cards of a launch loaded, so the player's opening stuck (the log:
// every open past 1.4 s had its cards collapse in the middle of it, none of the others did). Home's sections had the
// same (HomeSections.x).
static void collapse(UIView *cell, UIView *content, CGFloat natural) {
    objc_setAssociatedObject(cell, &kCollapsedKey, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    if (!content.hidden) content.hidden = YES;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    UIView *cell = (UIView *)self;
    UIView *content = cell.subviews.firstObject;
    if (!content || !isPlayerCard(content)) return result;
    collapse(cell, content, MAX(1, result.size.height));
    result.size = CGSizeMake(result.size.width, 0);

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    UIView *root = content.subviews.firstObject.subviews.firstObject;
    NSString *name = root ? NSStringFromClass(root.class) : @"nothing yet";
    if (![logged containsObject:name]) {
        [logged addObject:name];
        SGLog(@"redesign player: collapsed card root %@ (%lu kinds so far)", name, (unsigned long)logged.count);
    }
    return result;
}

// The cell's own passes may size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    NSNumber *natural = objc_getAssociatedObject(self, &kCollapsedKey);
    UIView *content = ((UIView *)self).subviews.firstObject;
    if (natural && content) collapse((UIView *)self, content, natural.doubleValue);
}

- (void)prepareForReuse {
    %orig;
    if (!objc_getAssociatedObject(self, &kCollapsedKey)) return;
    objc_setAssociatedObject(self, &kCollapsedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *content = ((UIView *)self).subviews.firstObject;
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = ((UIView *)self).bounds;
    content.hidden = NO;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
