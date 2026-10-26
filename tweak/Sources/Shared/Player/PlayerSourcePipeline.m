// The pipeline's source slot. It owns the one source processor Shared/Audio/SGAudioPipeline pulls through, and
// layers the two source-domain features:
//
//   - the lossless file swap (Shared/Lossless), reached by the canonical SGPlayerSetSourceSelector; and
//   - Karaoke (Shared/Sing), which registers a renderer through PipelineSource.h.
//
// Karaoke sits above the lossless swap: its renderer pulls its source through the lossless-applied pull, so a
// file still swaps in under it, and when Karaoke declines a buffer the slot falls through to the lossless path
// on its own. Spotify's own sound is pulled first and left unconsumed if the pull fails, so the pipeline's own
// path stays in charge.
//
// The epoch names the current source: a track, a seek, a pause or a route change each move it, so an anchor
// taken for the old one stops. The render-thread selector runs once per source buffer, after Spotify's own
// sound has been pulled, and may overwrite it.
#import <AudioToolbox/AudioToolbox.h>
#import <stdatomic.h>
#import "Shared/Audio/SGAudioPipeline.h"
#import "SpeedPitch.h"
#import "PipelineSource.h"

static _Atomic(uintptr_t) sg_selector;
static _Atomic uint64_t sg_epoch = 1;
static _Atomic uint64_t sg_frame;   // source frames since the epoch began
static double sg_rate = 44100;
static _Atomic(SGPipelineSingRenderer) sg_sing;

uint64_t SGPlayerSourceEpoch(void) {
    return atomic_load(&sg_epoch);
}

void SGPlayerInvalidateSource(void) {
    atomic_fetch_add(&sg_epoch, 1);
    atomic_store(&sg_frame, 0);
}

// The lossless-applied source pull: Spotify's own sound (or a swapped file) into `data`. This is what Karaoke
// pulls through, and what the slot returns when Karaoke is not rendering.
static OSStatus losslessPull(void *context, UInt32 frames, AudioBufferList *data, UInt32 *sounding) {
    const AudioTimeStamp *time = context;
    UInt32 sounded = frames;
    OSStatus pulled = SGAudioPipelinePullOriginalAvailable(frames, data, time, sounding ? &sounded : NULL);
    if (sounding) *sounding = sounded;
    if (pulled != noErr) return pulled;
    SGPlayerSourceSelector selector = (SGPlayerSourceSelector)atomic_load(&sg_selector);
    if (!selector) return noErr;
    uint64_t frame = atomic_load(&sg_frame);
    // Only a fully-sounded buffer carries the file swap, so a partly-silent look-ahead buffer (Karaoke reading
    // past what Spotify has decoded) is not swapped ahead of the song — matching the legacy chain, which stopped
    // the selector at the first silence.
    if (sounded == frames) selector(NULL, atomic_load(&sg_epoch), (double)frame, sg_rate, frames, data);
    atomic_fetch_add(&sg_frame, frames);
    return noErr;
}

// The pipeline's single source processor: Karaoke first (if it takes the buffer), else the lossless path.
static OSStatus sourceSlot(void *context, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    SGPipelineSingRenderer sing = atomic_load(&sg_sing);
    OSStatus status = noErr;
    if (sing && sing(frames, data, losslessPull, (void *)time, &status)) return status;
    return losslessPull((void *)time, frames, data, NULL);
}

static void refreshRate(void) {
    AudioStreamBasicDescription format = {0};
    if (SGAudioPipelineSourceFormat(&format) && format.mSampleRate > 0) sg_rate = format.mSampleRate;
}

// The source processor, not the pull processor: SpeedPitch owns the single pull slot, and its chain pulls the
// source through here. A no-op until Spotify has wired a supported source, and the pipeline drops it on every
// output start or format change, so Sing's prepare hook calls this again each time the output is prepared.
void SGPipelineSourceEnsureInstalled(void) {
    refreshRate();
    SGAudioPipelineSetSourceProcessor(sourceSlot, NULL);
}

void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) {
    atomic_store(&sg_selector, (uintptr_t)selector);
    // Best effort now (so a file going live mid-track takes effect at once); re-done at the next output prepare.
    SGPipelineSourceEnsureInstalled();
}

void SGPipelineSetSingRenderer(SGPipelineSingRenderer renderer) {
    atomic_store(&sg_sing, renderer);
}
