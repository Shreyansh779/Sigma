// The one public face of the speed/pitch/gain hub and the lossless source selector. The master switch
// (SGAudioPipelineEnabled, read once at launch) decides which backend answers: off, the legacy per-feature
// tap (SpeedPitch.x); on, the unified pipeline client (SpeedPitchPipeline.x + PlayerSourcePipeline.m).
// Nothing else in the mod knows the difference — it all calls these canonical SGPlayer* names.
#import "SpeedPitch.h"
#import "SpeedPitchImpl.h"
#import "Shared/Audio/SGAudioPipeline.h"

static inline BOOL pipe(void) { return SGAudioPipelineEnabled(); }

double SGPlayerSpeed(void) { return pipe() ? SGPlayerSpeedPipeline() : SGPlayerSpeedLegacy(); }
void SGSetPlayerSpeed(double speed) { if (pipe()) SGSetPlayerSpeedPipeline(speed); else SGSetPlayerSpeedLegacy(speed); }
BOOL SGPlayerSpeedAllowed(void) { return pipe() ? SGPlayerSpeedAllowedPipeline() : SGPlayerSpeedAllowedLegacy(); }
float SGPlayerPitch(void) { return pipe() ? SGPlayerPitchPipeline() : SGPlayerPitchLegacy(); }
void SGSetPlayerPitch(float semitones) { if (pipe()) SGSetPlayerPitchPipeline(semitones); else SGSetPlayerPitchLegacy(semitones); }
BOOL SGPlayerPitchAvailable(void) { return pipe() ? SGPlayerPitchAvailablePipeline() : SGPlayerPitchAvailableLegacy(); }
BOOL SGPlayerPitchFollowsSpeed(void) { return pipe() ? SGPlayerPitchFollowsSpeedPipeline() : SGPlayerPitchFollowsSpeedLegacy(); }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) { if (pipe()) SGSetPlayerPitchFollowsSpeedPipeline(follows); else SGSetPlayerPitchFollowsSpeedLegacy(follows); }
void SGPlayerSetGain(float gain) { if (pipe()) SGPlayerSetGainPipeline(gain); else SGPlayerSetGainLegacy(gain); }

uint64_t SGPlayerSourceEpoch(void) { return pipe() ? SGPlayerSourceEpochPipeline() : SGPlayerSourceEpochLegacy(); }
void SGPlayerInvalidateSource(void) { if (pipe()) SGPlayerInvalidateSourcePipeline(); else SGPlayerInvalidateSourceLegacy(); }
void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) { if (pipe()) SGPlayerSetSourceSelectorPipeline(selector); else SGPlayerSetSourceSelectorLegacy(selector); }
