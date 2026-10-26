// Speed and pitch: two sliders in the more button's menu, done to Spotify's sound, under either look.
// Nothing here draws on a Spotify screen of its own: the block goes into Spotify's own context menu
// sheet, and the rest is audio.
//
//     SpeedPitchMenu.x   the expandable row and its two sliders, put into Spotify's context menu, and under
//                        the redesign the Animated artwork switch under them
//     SpeedPitch.x       speed and pitch done to Spotify's audio, between its mixer and its speaker unit, and
//                        Spotify's outputs kept apart, one of them the music's (SGPlayerMusicOutput)
//     SGTimePitch.m      Apple's time and pitch unit, pulling the mixer or working in place
//
// Speed and pitch last until Spotify quits; neither is stored.
// Threading: main thread only, except what SGTimePitch.h says runs on the render thread.
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

// Whether a context menu sheet is the player's ⋯ card: the first to come up within a few seconds of a tap on
// the player's more button (SpeedPitchMenu.x watches it under either look); decided once per menu.
BOOL SGPlayerMenuIsPlayers(UIViewController *menu);
// The next context menu sheet is the player's ⋯ card, as a tap on the ⋯ would make it: for the redesign's ⋯,
// whose menu runs Spotify's ⋯ action from code (Redesigned/ContextMenu) and keeps the touch from the ⋯.
void SGPlayerMenuMarkPlayers(void);
// Whether the sheet is shown as the system menu instead, unseen under it (Redesigned/ContextMenu), whose own
// items then stand in for the block, which stays out of it. Defined by the redesign; NO under the native look
// and once the sheet itself is shown.
BOOL SGPlayerMenuReplaced(UIViewController *menu);
// The speed Spotify's sound plays at, 1 when normal.
double SGPlayerSpeed(void);
// Whether speed can apply: Spotify's output was taken over when it wired it.
BOOL SGPlayerSpeedAllowed(void);
void SGSetPlayerSpeed(double speed);
// Semitones Spotify's output is moved by, 0 when it is not.
float SGPlayerPitch(void);
void SGSetPlayerPitch(float semitones);
// Speed and pitch move together, like a record, by resampling rather than the time stretch. On until
// switched off, from the switch under the two sliders.
#define SGKeyPitchFollowsSpeed @"spotifyglass.speed.pitchFollows"
BOOL SGPlayerPitchFollowsSpeed(void);
void SGSetPlayerPitchFollowsSpeed(BOOL follows);
// Whether the output could be reached to change its pitch.
BOOL SGPlayerPitchAvailable(void);
// The mod's own volume on Spotify's sound, 0 to 1, 1 when normal: the sleep timer's fade (SleepTimer.h).
// Any thread. The sound moves to it within half a second and never in a step. It scales what the speaker
// unit plays, in the output's own format, so a Connect device is left as it was, and it
// does nothing when Spotify's output was never reached (AudioOutputUnitStart not rebound). Not stored.
void SGPlayerSetGain(float gain);
// The audio effects' reverb as the menu sets it, 0 to 100, 0 while it is off. Any amount turns the effects and
// the reverb on with it; 0 turns the reverb off and leaves the rest of the effects as they were.
float SGPlayerReverb(void);
void SGPlayerSetReverb(float amount);

// The redesign's Animated artwork, switched in the same block: whether the player offers the switch (the
// redesign is running and its background is Fluid, Animated or Visualizer, the three that share a field),
// whether it is on, and switching it, which applies at once and is stored as the Background choice (off is
// Fluid, and from the Visualizer changes nothing). Defined by
// Redesigned/Player/PlayerMotion.x; NO from the first under the native look.
BOOL SGPlayerMenuOffersAnimatedArtwork(void);
BOOL SGPlayerMenuAnimatedArtwork(void);
void SGPlayerMenuSetAnimatedArtwork(BOOL on);
// The speed, pitch and reverb sliders and Pitch follows speed, in a popover from `from` (the redesign's ⋯).
void SGPlayerShowSpeedPitchPanel(UIView *from);
// Source selector (the lossless file swap, Shared/Lossless). Registered callback code must live for the
// process lifetime. Called after each successful, non-silent native mixer pull on the music output only.
// The native mixer is still drained exactly once. data is planar Float32 in the client format; replace
// a complete span or leave it untouched. No allocation, file I/O, Objective-C or waits here.
// sourceFrame is an output-local counter, not track position. The caller must prove a recording/frame
// anchor before enabling replacement. No production caller currently does so.
typedef void (*SGPlayerSourceSelector)(AudioUnit output, uint64_t epoch, double sourceFrame,
                                      double sampleRate, UInt32 frames, AudioBufferList *data);
void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector);
uint64_t SGPlayerSourceEpoch(void);
// Any thread, including render. Invalidate on every seek/skip/recording occurrence/policy cancellation.
// Audio-output lifecycle changes also invalidate internally. An already admitted render may finish.
void SGPlayerInvalidateSource(void);
