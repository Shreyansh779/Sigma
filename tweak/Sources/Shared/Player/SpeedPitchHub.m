// The one public face of the speed/pitch/gain hub and the lossless source selector. The master switch
// (SGAudioPipelineEnabled, read once at launch) decides which backend answers: off, the legacy per-feature
// tap (SpeedPitch.x); on, the unified pipeline client (SpeedPitchPipeline.x + PlayerSourcePipeline.m).
// Nothing else in the mod knows the difference — it all calls these canonical SGPlayer* names.
#import "SpeedPitch.h"
#import "SpeedPitchImpl.h"
#import "Shared/Audio/SGAudioPipeline.h"

// Not `pipe` — that is POSIX pipe(2) from <unistd.h>, pulled in transitively.
static inline BOOL onPipeline(void) { return SGAudioPipelineEnabled(); }

double SGPlayerSpeed(void) { return onPipeline() ? SGPlayerSpeedPipeline() : SGPlayerSpeedLegacy(); }
void SGSetPlayerSpeed(double speed) { if (onPipeline()) SGSetPlayerSpeedPipeline(speed); else SGSetPlayerSpeedLegacy(speed); }
BOOL SGPlayerSpeedAllowed(void) { return onPipeline() ? SGPlayerSpeedAllowedPipeline() : SGPlayerSpeedAllowedLegacy(); }
float SGPlayerPitch(void) { return onPipeline() ? SGPlayerPitchPipeline() : SGPlayerPitchLegacy(); }
void SGSetPlayerPitch(float semitones) { if (onPipeline()) SGSetPlayerPitchPipeline(semitones); else SGSetPlayerPitchLegacy(semitones); }
BOOL SGPlayerPitchAvailable(void) { return onPipeline() ? SGPlayerPitchAvailablePipeline() : SGPlayerPitchAvailableLegacy(); }
BOOL SGPlayerPitchFollowsSpeed(void) { return onPipeline() ? SGPlayerPitchFollowsSpeedPipeline() : SGPlayerPitchFollowsSpeedLegacy(); }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) { if (onPipeline()) SGSetPlayerPitchFollowsSpeedPipeline(follows); else SGSetPlayerPitchFollowsSpeedLegacy(follows); }
void SGPlayerSetGain(float gain) { if (onPipeline()) SGPlayerSetGainPipeline(gain); else SGPlayerSetGainLegacy(gain); }

uint64_t SGPlayerSourceEpoch(void) { return onPipeline() ? SGPlayerSourceEpochPipeline() : SGPlayerSourceEpochLegacy(); }
void SGPlayerInvalidateSource(void) { if (onPipeline()) SGPlayerInvalidateSourcePipeline(); else SGPlayerInvalidateSourceLegacy(); }
void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) { if (onPipeline()) SGPlayerSetSourceSelectorPipeline(selector); else SGPlayerSetSourceSelectorLegacy(selector); }
