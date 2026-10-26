// The redesign names the album for Shared/AlbumQueue. The redesign's ⋯ is the pinned one every entity page
// puts in its corner (Redesigned/Kit/SGRActionRow); its tap is recorded with the page it is on, and that page
// is a CreativeWorkTemplateView whose album URI SGAlbumQueueAlbumForPage reads. A playlist, artist or episode
// page yields nil there, so the row appears on albums alone.
//
// Declared low in Shared/AlbumQueue/AlbumQueue.h, defined here: nil under the native look, where no pinned ⋯
// exists, so Shared can ask without importing the redesign.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Shared/AlbumQueue/AlbumQueue.h"

NSString *SGAlbumQueueRedesignSource(void) {
    if (!SGRedesignedUI()) return nil;
    UIView *page = SGRPinnedMoreRecentPage();
    return page ? SGAlbumQueueAlbumForPage(page) : nil;
}
