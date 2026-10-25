#pragma once
#import <AudioToolbox/AudioToolbox.h>
#import <stdbool.h>

// The unified pipeline has one source slot (Shared/Audio/SGAudioPipeline). The legacy hub gave the lossless
// file swap and Karaoke separate layers — Karaoke's stage pulled its source through the lossless selector. The
// pipeline keeps that layering in one slot: PlayerSourcePipeline.m owns the slot and runs Karaoke's renderer
// above the lossless path, so when Karaoke is on it wins and still pulls Spotify's (or the file's) sound through,
// and when it declines a buffer the slot falls through to the lossless path on its own.

// Pulls the chain's source into `data` (two float mono buffers): the lossless-swapped sound when a file is live,
// otherwise Spotify's mixer. With `sounding`, stops at the first silent source chunk and reports its prefix.
// Render thread.
typedef OSStatus (*SGPipelineSourcePull)(void *context, UInt32 frames, AudioBufferList *data, UInt32 *sounding);

// Karaoke's render: fills `data` by pulling through `pull` (with `pullContext`), setting `*status`, and returns
// true; or returns false to leave the buffer to the lossless path untouched. Render thread. Immutable,
// process-lifetime; set once when the pipeline is on, NULL clears it.
typedef bool (*SGPipelineSingRenderer)(UInt32 frames, AudioBufferList *data, SGPipelineSourcePull pull,
                                       void *pullContext, OSStatus *status);
void SGPipelineSetSingRenderer(SGPipelineSingRenderer renderer);

// Installs the shared source processor into the pipeline. The pipeline clears its source processor on every
// output start and format change, so this must run again each time the output is (re)prepared — Sing's prepare
// hook calls it. Off-render only; a no-op until Spotify has wired a supported source.
void SGPipelineSourceEnsureInstalled(void);
