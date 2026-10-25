#pragma once
// Two backends for the speed/pitch/gain hub and the lossless source selector live in the binary at once:
//   - the legacy per-feature tap (SpeedPitch.x), which owns Spotify's outputs and rebinds the audio imports
//     itself, exactly as the mod has always done; and
//   - the unified pipeline client (SpeedPitchPipeline.x + PlayerSourcePipeline.m), which hands that role to
//     Shared/Audio/SGAudioPipeline.
// SpeedPitchHub.m picks one at launch from SGAudioPipelineEnabled() (the master switch, read once). The rest
// of the mod calls the canonical SGPlayer* names (SpeedPitch.h); it never sees which backend answers. These
// are the two backends it dispatches to; a `…Legacy` and a `…Pipeline` for each colliding symbol.
#import <AudioToolbox/AudioToolbox.h>
#import "SpeedPitch.h"

double SGPlayerSpeedLegacy(void);
void SGSetPlayerSpeedLegacy(double speed);
BOOL SGPlayerSpeedAllowedLegacy(void);
float SGPlayerPitchLegacy(void);
void SGSetPlayerPitchLegacy(float semitones);
BOOL SGPlayerPitchAvailableLegacy(void);
BOOL SGPlayerPitchFollowsSpeedLegacy(void);
void SGSetPlayerPitchFollowsSpeedLegacy(BOOL follows);
void SGPlayerSetGainLegacy(float gain);
uint64_t SGPlayerSourceEpochLegacy(void);
void SGPlayerInvalidateSourceLegacy(void);
void SGPlayerSetSourceSelectorLegacy(SGPlayerSourceSelector selector);

double SGPlayerSpeedPipeline(void);
void SGSetPlayerSpeedPipeline(double speed);
BOOL SGPlayerSpeedAllowedPipeline(void);
float SGPlayerPitchPipeline(void);
void SGSetPlayerPitchPipeline(float semitones);
BOOL SGPlayerPitchAvailablePipeline(void);
BOOL SGPlayerPitchFollowsSpeedPipeline(void);
void SGSetPlayerPitchFollowsSpeedPipeline(BOOL follows);
void SGPlayerSetGainPipeline(float gain);
uint64_t SGPlayerSourceEpochPipeline(void);
void SGPlayerInvalidateSourcePipeline(void);
void SGPlayerSetSourceSelectorPipeline(SGPlayerSourceSelector selector);
