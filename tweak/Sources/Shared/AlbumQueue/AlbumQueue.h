// Add whole album to queue: a row on an album's ⋯ context menu that resolves the album's tracks and
// bulk-queues them, under either look (AlbumQueueMenu.x says how the row reaches each look's menu).
//
//     AlbumQueue.m          resolves the album and runs Spotify's bulk queue command, one request at a time
//     AlbumQueueContext.m   the strict context-resolve parser and the album URI check
//     AlbumQueueMenu.x      the row, the Dynamic-Island confirmation notice, and the row's place in the sheet
//     AlbumPage.swift       the album URI a CreativeWorkTemplateView page carries, read by reflection
//
// Threading: main thread only.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// A Spotify album URI (spotify:album:<22 base62>); nothing else.
BOOL SGAlbumQueueIsAlbumURI(NSString *uri);
// The context-resolve answer's track URIs, order and repeats kept; nil with *error set when the album did
// not come back whole (a partial page fails, so half an album is never queued).
NSArray<NSString *> *SGAlbumQueueTrackURIs(id context, NSString *uri, NSString **error);
// Resolves the album, then uses Spotify's bulk queue command. `done` runs on main, once, with the number
// of songs added or an error to show.
void SGAlbumQueueAdd(NSString *uri, void (^done)(NSUInteger count, NSString *error));

// The confirmation notice shown as a glass capsule under the Dynamic Island.
@interface SGAlbumQueueNotice : UIView
+ (void)showIn:(UIWindow *)window title:(NSString *)title detail:(NSString *)detail symbol:(NSString *)symbol;
@end

// Spotify's ⋯ buttons. An album header's ⋯ identifier ends in the album's id.
#define SGAlbumQueueButtonPrefix @"Components.UI.ContextMenuButton-"

// The album URI the page controller `page` is on carries (AlbumPage.swift reflection), an album only; nil for
// a playlist, artist, episode or anything whose page is not an album's. Walks up from `page` for the controller.
NSString *SGAlbumQueueAlbumForPage(UIView *page);
// Records the album whose ⋯ was just tapped, read once the context menu sheet appears. Each look's own hook
// sets it: the native album header ⋯ (Native/AlbumQueue), the redesign's pinned ⋯ (SGAlbumQueueRedesignSource).
void SGAlbumQueueMarkAlbum(NSString *uri);
// The album whose pinned ⋯ the redesign recorded a tap on, or nil. Defined by the redesign; nil under the
// native look, where no pinned ⋯ exists. Declared here so Shared can ask without importing Redesigned.
NSString *SGAlbumQueueRedesignSource(void);
