# Working on the mod

## Layout

    tweak/                      the Theos project: Makefile, control, the bundle filter plist
    tweak/Sources/Core/         what every file builds on: logging, preferences, view-tree walking, glass panes, the
                                look this launch runs (SGUIMode.h), the forced-flag registry (SGFlagForce.h) and C
                                functions Spotify imports hooked by rebinding its import slots (SGRebind.h)
    tweak/Sources/Headers/      reverse-engineered Spotify classes, one header each, only the selectors used
    tweak/Sources/Settings/     the Mod Settings framework: SGPage (a page on Spotify's stack), SGModPage (sections
                                of rows: switches, choices, sliders, links, and rows shown only while a switch
                                is on), SGPageStyle (Spotify's list look), SGGlowSwitch
    tweak/Sources/Shared/       what works the same with either look, see Layers below
    tweak/Sources/Native/       tweaks on Spotify's own screens, running only while Redesigned UI is off
    tweak/Sources/Redesigned/   the redesign, running only while Redesigned UI is on
    tweak/Sources/App/          what brings the layers together: Mod Settings' root and composed pages, the Mod page,
                                signing, the welcome tour
    tweak/Sources/Diagnostics/  screen dumps, the tree server and the main thread hang sampler of FLEX builds
    extension/AppGroups/        a dylib loaded by Spotify and its home screen widget that moves Spotify's App Groups
                                into a group the re-signed IPA has; without it the widget stays a placeholder
    extension/LiveActivity/     the Live Activity widget, a WidgetKit extension of its own, built into the IPA by
                                scripts/build-extension.sh (Xcode's Swift; an IPA built without Xcode has no card)
    scripts/                    pipeline.sh (build + inject), insert-dylib.py (a load command into
                                Spotify's widget), install.sh (sign + install), record-trees.py, record-session.py,
                                dump-log.sh, extract-flags.py, build-extension.sh (the Live Activity's appex and its App Intents
                                metadata), merge-appintents.py (that metadata into Spotify's own)
    trees/                      recorded view trees, one per screen; the input for every new hook. trees/clean/ holds
                                the numbered snapshots per screen of record-session.py, taken of Spotify as it came
    plist/                      Info.plist overrides merged into the app (turns UIDesignRequiresCompatibility off, allows
                                Live Activities and Music Haptics)
    vendor/                     AutoFLEX deb; audio/, the third-party C of the audio effects (libbs2b, WDL's EEL2) and
                                the EEL2 parser of the mod's own, built by its own Makefile into a static library the
                                tweak links (its README names the upstream commits and the licenses)
    ipa/, out/                  decrypted Spotify IPA in, built IPAs out (both gitignored)

`tweak/Sources/Shared/Flags/SGFlagList.m` is generated from the IPA and gitignored, as are the
recorded trees: both are read out of Spotify's own binary and belong to whoever built them.

## Layers

The mod has two looks, picked by Redesigned UI in Appearance: Spotify's own screens with the mod's
tweaks on them, or the redesign, which starts from a clean sheet. What does not draw on Spotify's
screens works under both. So the sources are four layers, each a directory of features:

    Shared/       works the same with either look
    Native/       Spotify's own screens tweaked; every %ctor starts with `if (!SGNativeUI()) return;`
    Redesigned/   the redesign; every %ctor starts with `if (!SGRedesignedUI()) return;`
    App/          Mod Settings' root and the pages that combine the layers, the Mod page, the tour

`SGRedesignTested()` (Core/SGUIMode.h) is YES from iOS 26: the redesign is Liquid Glass, and
`UIGlassEffect` is the system's, so on an older OS the glass calls fall back to a blur and the redesign
runs untested against an older UIKit (issue #37, an iOS 17 scene-update watchdog). Below 26 it can still
be picked: App/Pages.m's restart alert and the tour's note under the cards say it is untested first, and
`SGSetRedesignedUI()` stores `SGKeyRedesignUntested` along with the switch. Without that key the redesign
does not run below 26, and `SGRedesignedUI()` turns off a switch stored before the warning existed.

The two looks never run together, so each hooks the same Spotify class in its own way, and a part of
the look is edited on its own side without touching the other: where both need the same thing, each
has its own copy (the tab bar's composition and its editor, the lyrics page's glass, the soft top edge,
AMOLED, the accent colour), under its own names (SG… native, SGR… redesign) and its own keys. The imports run
one way, Core <- Settings <- Shared <- Native | Redesigned <- App, and `scripts/check-layers.sh`, run
by tweak/Makefile before every build, fails on any other. A layer below that needs something from one
above takes it through a registry in Core (forced flags, SGFlagForce.h) or a function declared low and
defined high (SGOpenModSettings).

A feature is a directory in its layer holding everything about one area of the app:

    <Feature>.h            the keys of its switches, and the functions other files may call
    <Something>.x          the hooks, one file per screen or mechanism, each ending in its own %ctor
    <Feature>Settings.m    its Mod Settings page, or its sections for the page of the part it changes, built from
                           the rows in Settings/SGModPage.h; App/Pages.m puts them on the page
    <Model>.m              plain Objective-C the hooks and the page share, where there is any

Shared:

    Privacy/      telemetry blocking and its counters, and the Search switches that force their flags off (Clutter.m)
    Flags/        Spotify's remote-config flags: the provider hook, the generated table, the All flags page
    Lyrics/       the lyrics engine for the redesign's Apple Music style lyrics and the lock screen: lines read from
                  color-lyrics and the player's clock (KaraokeSource.x), words timed by estimate inside Spotify's line
                  times (KaraokeTiming.m, which splits Thai, Lao, Khmer and Burmese at the system's dictionary words), which line to name where two voices sing at once (the one that came in first,
                  for the lock screen and the Live Activity), a line in another alphabet in Latin letters, offline by Apple's
                  transforms, kanji read the Japanese way in a song with kana (Romanise.m; checked on the simulator by
                  harness/lyrics' -romanise), and the Lyrics page's parts. Lines are kept in time order
                  whatever order a source lists them in. The Lyrics page's Delay (Timing, 0 to 1000 ms, either look)
                  shows every line that much later than the song, for Bluetooth headphones: whatever times lines
                  against the position takes it off first (the redesign's lyrics view and its word sweep, the lock
                  screen's line and artwork, the Live Activity, the native look's lyrics page for local files), and a
                  tap on a line seeks to its start plus the delay. Karaoke's audio, the scrubber and the lyrics preview
                  are left alone. It is read at every use, so a change applies at once (checked by harness/lyrics' -check). With EeveeSpotify injected (SGEeveeSpotifyInjected), its lyrics
                  answer Spotify's requests and the mod's sources and its own requests stand aside
    LyricsSources/ the sources lyrics come from, asked in the order the Lyrics page puts them in and merged into the
                  best answer (LyricsSources.m, the list to drag in LyricsSourcesPage.m): Apple Music's TTML from
                  BiniLyrics.m (now lrc.red: first the TTML filed under Spotify's ISRC for the track, from
                  SGSpotifyISRC in Haptics/SystemMusicHaptics.x, else its search by name) and Unison.m, read by SGTTML.m,
                  which carries a second voice and the backing vocals, and in its head Apple's translation and its
                  pronunciation of a line, each keyed to the line by its itunes:key or lrc:key, the pronunciation
                  timed word by word (the translation taken in the Lyrics page's language); Musixmatch.m, matched by
                  Spotify's track id with an anonymous token, word timed where it has richsync; NetEase.m, word timing from yrc for what the others only line time; LrcLib.m, open and
                  keyless and timed by the line, the floor under the rest. SpicyLyrics.m, Spicy Lyrics' Developer Platform
                  by track id on the user's own publishable key (Keychain), syllable timed where it has a sync, with
                  its pronunciations and translations; its credit, which its terms require, shows whatever Show source
                  says and opens the uploader's and maker's pages from a tap (both looks), its answers and misses are
                  kept per track, a rate limit is waited out and a refused key is left for 10 min, its reason on the
                  source's row; checked on the Mac against harness/spicy-lyrics/. QQMusic.m (line timed LRC) and KuGou.m (word timed KRC, unpacked with
                  zlib and read by NetEase.m's parser) for Chinese and other Asian songs, matched by title, singer
                  and length; checked on the Mac against harness/lyrics-sources/. color-lyrics is answered with whichever won
                  (LyricsHook.x): Spotify's own 200 gets our lines swapped in; a track Spotify's metadata says has none has
                  its request sent to a donor track that does, so the reply is a real 200 (a 404 answered as a 200 in the
                  delegate alone never showed the card on 9.1.78); a 404 for a track not seen yet is held until the chain
                  answers. The card list the server sends per track (scrollsita) carries a lyrics section only for tracks
                  Spotify has lyrics for, so one is added to any list without it: that is what makes the player ask for the
                  lyrics and show the card. has_lyrics is forced on for every track, the walk starts at the track change
                  for it and the next, and the player's card-loading timeout flag is forced to its 5 s maximum while a
                  source is on. In the redesign, with a translation language chosen, lines kept for the lyrics view with
                  no translation of their own take Musixmatch's community translations (Musixmatch.m), whichever
                  source won, Spotify's own included: matched by the line's folded text, as copies kept in place of the
                  lines (KaraokeSource.x), which the view picks up
    LockScreenLyrics/ the line being sung in the system's now playing, and on iOS 26 the lyrics as the lock screen's
                  full-screen artwork (LyricsArtwork.x): a new artwork ID per line, its 3:4 H.264 clip (the line and the
                  next one dimmed over the blurred cover, SGLyricsClip.m) written only when the lock screen asks for it,
                  Still (one frame) or Animated (15 fps). The backdrop is blurred small and drawn large, on the CPU as the
                  lock screen asks in the background; previews are drawn on a queue apart from the clips, and while the
                  lock screen is asking, the next line's preview and clip are drawn ahead and a ready preview is handed
                  over at once. iOS still shows the plain cover for about half a second at each change of artwork. Picking it or another artwork applies at once. Rendered on the Mac against harness/lyrics-clip/. What reaches the
                  system's now playing through this hook and Player/NowPlayingExtras.x is checked by harness/now-playing/
    Navigation/   the page transition fix (PageTransition.x), opening a spotify: link (Links.x), and either look's
                  Add a Tab sheet (AddTabSheet.m) with the icons a tab can wear, Encore's glyphs or SF Symbols
                  (TabIcons.m). The sheet runs in the simulator in harness/addtab/
    ConnectDiscovery/  Bonjour resolves local Spotify Connect receivers. When Spotify's own mDNS send
                  fails without the multicast entitlement, a bounded round sends its query by IPv4/IPv6
                  unicast to all resolved receivers and replays validated replies to Spotify's socket.
                  A short wait also catches receivers still resolving. Connected sockets are left alone.
                  The IPA declares Connect and Google Cast Bonjour service types; pipeline.sh keeps the
                  IPA's existing types. This bridge handles Connect only; Cast is Bonjour-declared but
                  has no equivalent packet bridge here.
    Sing/         Karaoke (Sing in the code and its keys), a song's vocals turned down while it plays (Sing.h lists
                  its files): one voice model (Mel-Band RoFormer, MIT, exported by Vitrine for the Neural Engine and
                  palettized to 6 bits: separator-ane.mlmodelc, 210 MB, from Hugging Face; on a FLEX build a copy in
                  Sing/dev/ comes first) downloaded and checked file by file over Wi-Fi unless cellular is allowed,
                  a stop keeping what came in for the next download to carry on from; the 489 MB model downloaded
                  before is kept and loaded on the CPU alone until this one is in (the Voice model row then reads
                  Update available), and deleted as its download ends or at a launch that finds both
                  (SGSingRemoveOldModel, which logs the space freed) or by hand from the Delete the old voice model row of the
                  Karaoke page, shown while the old files are there (SGSingDeleteOldModel; it switches Karaoke off when it was running
                  on them, and a folder from before Sigma was named spoti.pw is moved across first), Sing moving to the new one at its next load;
                  loaded only while Spotify
                  is active (SGSingLoader.m), on any iPhone with iOS 18, a CPU copy first and warmed, only with 1 GB left to the
                  process (no floor on the iPhone's memory: both copies warm add 0.1 GB of footprint), then on Automatic, where the iPhone has a
                  Neural Engine, a Neural Engine copy of the same model beside it, which takes every window once it is
                  in, in the background too, each load with a deadline and kept a minute after the mic goes off; the
                  Neural Engine copy loads only with 0.5 GB left to the process, its first load after every install
                  compiling it for up to ten minutes while Karaoke runs on the CPU (while it loads, the CPU's falling
                  behind spends none of the 8 s after which Karaoke gives a song up, nor counts toward its three in a
                  row), unless Prepare after updates (on by default) compiled it already: with the model in and the mic off, 15 s after
                  Spotify comes to the front and below the thermal state Serious, the Neural Engine copy alone loads once for this
                  iOS and install and is let go (22 s on a fair iPhone 15 Pro, 48-65 s on a serious one; a want meanwhile takes that
                  load over), so the mic's copy loads in 0.3 s; Karaoke's status reads "On, Neural Engine" or "On, CPU", and "Off ·
                  preparing for the Neural Engine" while it compiles ahead, and it is dropped for the launch, the CPU copy carrying on, once it fails to load, warm up or
                  run a window (one that falls behind keeps its place); Runs on is Automatic or CPU only, the GPU and
                  Neural Engine choices stored before read as Automatic; the STFT around it on Accelerate,
                  and an engine that stands in Speed and pitch's chain between Spotify's mixer and its output
                  (SGPlayerSetStage), pulls the mixer a few seconds ahead of what plays, never past sound Spotify has not
                  decoded yet (a part of a pull ahead its mixer marks silent is left out of the lead and read again at the
                  next render, so a slow network fills the lead more slowly and a stall plays through on it; "sing: read
                  ahead:" in the log, the first three times and then a count a minute), separates two-second windows
                  there on a worker thread and mixes the vocals down on the render thread. Spotify's clock has the lead
                  taken off (SPTPlayerState's positionAsOfTimestamp): the lead held when that line of the clock began
                  (the same position run on at the same speed, however often a state is stamped again), less what was
                  dropped since, as the player reports on a change and not as it plays (SGSingLeadOf, read by every
                  correction); run on (-position), the lead comes off after running on and never below 0, so a track
                  reached as the last one ends, reported while the lead still holds that end, stays at 0 until its first
                  frame plays rather than running on from the title change (every 5 s a "sing: clock:" log line sets Spotify's clock against what the engine pulled
                  and played, and every lyrics seek logs where it was sent and where it landed), and a seek, a skip or a stop drops it.
                  Until the seek or skip lands (Spotify reports the target or the new track, or 5 s pass) nothing is
                  read ahead, as Spotify's mixer still hands over what came before it; the queue's next track arriving
                  up to 12 s early is crossfade and keeps the lead, another track arriving early drops it; on the
                  queue's last track (no next, no repeat) the lead drains at half speed so it has played out a second
                  before Spotify's decoder reaches the end (SGSingEngineSetLeadCap). Not separating (stopped, held, resting at As sung,
                  standing aside), the engine plays the lead it holds on as it is, dry, the clock still corrected, so no
                  part of the song is skipped; it lets it go at a pause, where Sing.x seeks Spotify back to what was
                  heard (and so when the headphones it played on go), or with a seek, a skip or the output stopping, and builds one only when it separates.
                  Karaoke stands aside, the model kept, over AirPlay, for what is not a song, and while Spotify plays
                  but its output has not rendered for 3 s (Connect to another device: "Not on this iPhone"); an
                  interruption (a call, Siri, another app's audio) holds the worker and keeps the lead until iOS says it
                  ended or the sound comes back, Spotify deciding whether to resume. At As
                  sung with Spatial voice off it rests (held as for the heat, the model kept a minute as for a mic
                  switched off, "sing: rests" in the log) unless the Karaoke page's card is on screen with Spotify in
                  front: its reads of its two lines (SGSingReadLevels; the card's traces, not the lyrics, which are no
                  viewer) keep Karaoke separating the playing song, so the lines move and the slider is heard at once
                  ("sing: separates again"), and a second after the page is popped, covered or in the background it
                  rests again. From the
                  thermal state Serious up Karaoke is held and lets the model go,
                  unless Ignore heat warnings is on, and runs again at Fair. Spatial
                  voice holds the separated vocals in front as the head turns: HeadGestures' motion gives the yaw off a
                  front that follows the head (Back in front, 5 s unless set), and the render thread pans the vocals' middle at equal power,
                  narrowed, with the far ear up to 0.65 ms late and low-passed; it stands down for iOS's own spatial
                  audio. Its Sound section sets Distance (the voice down by the square root of the distance), Room
                  (a wet-only AUReverb2 fed the voice's middle, emptied by a seek) and Instruments width (the rest's side
                  scaled); off, all three leave the song exactly as it was. The Spatial voice page's preview (SGSpatialPreview.m) turns a disc of dots under the listener by
                  the same front (SGSpatialVoiceAngle, SGSingEngine.h), on Core Animation alone and only while the page
                  shows. The mic is on the redesign's lyrics (Redesigned/Lyrics/SGRSingButton.m). Tested on the Mac
                  against harness/sing/ (the lead, its cap, a slow decoder, a track boundary, spatial voice and its front without the model: `build/sing spatial`; the
                  model as both copies with `ane`, as the CPU's alone with `cpu`), the download against its download/
                  (`update` for the old model kept until it, `dev` for the dev folder), the pages in the simulator against harness/spatial-page/
    Player/       the player's open and close announced (PlayerEvents.x), what the player is doing read through
                  one hook for every feature that wants it (PlayerState.x), the last track played for the settings
                  pages' previews to show when nothing plays (SGLastTrack.m), the lock screen widget's flags, and in the
                  more button's menu Speed and pitch: both done to Spotify's audio by Apple's time and pitch unit, put
                  between its mixer and its RemoteIO unit by taking over the connection Spotify makes between them
                  (SpeedPitchMenu.x, SpeedPitch.x, SGTimePitch.m). Spotify runs a chain per sample rate, so a local
                  file at another rate can have two RemoteIO units running at once: SpeedPitch.x keeps a record
                  per unit (its own mixer, sample time, largest slice and formats; AudioOutputUnitStop and
                  AudioComponentInstanceDispose rebound too, a disposed unit forgotten after its render in progress)
                  and names one the music's (SGPlayerMusicOutput), the one Spotify started or connected last, or
                  one with sound when that one has had none for a second; speed and pitch, Karaoke's stage, the audio
                  effects and Music Haptics follow it (SGPlayerWatchMusicOutput), and the other plays as Spotify
                  made it. A connection whose formats the callback cannot take (not float with a buffer per channel,
                  more than two channels, or a mixer at another rate than the unit) gets Spotify's own connection
                  back. Each start, stop and dispose is logged as `audio:` with its formats and where the processors
                  are. Pitch follows speed (on until switched off,
                  spotifyglass.speed.pitchFollows) plays the speed through Apple's Varispeed instead, faster and higher
                  together like a record; Varispeed also carries 1x while it is on, so a return to normal speed changes
                  nothing, and the stretch is left for pitch alone at 1x, the two swapped only through a reset. A new
                  format on either side of the output while it runs (a route to another rate, Spotify handing it
                  another one) makes the unit again for it, and until then the sound passes as it is. harness/speed's
                  `two` runs a 44.1 and a 48 kHz chain at once. Under the
                  sliders a Reverb slider sets the audio effects' reverb amount (spotifyglass.dsp.reverb.amount), turning
                  the effects and the reverb on with it. The block goes into Spotify's own context menu sheet
                  and is drawn from its own measures, not the Kit's, so it sits there under either look. Tested on the
                  Mac against harness/pitch/ and in the simulator against harness/speed/ and harness/menu/. Under the
                  redesign, with the player's background Fluid or Animated, a row under the block switches Animated
                  artwork at once, through functions the redesign's PlayerMotion.x defines. The redesign shows that
                  sheet as the system menu (Redesigned/ContextMenu), whose own items stand in for the block, so the
                  block stays out of it unless the sheet itself is shown (SGPlayerMenuReplaced). Switch to video,
                  the chip over the title of a song with a music video, is hidden under either look on request
                  (VideoSwitch.x, spotifyglass.hide.videoSwitch), by its identifier in FloatingElementsUnit.
                  The sleep timer (SleepTimer.m, set from the Live Activity) pauses Spotify at a time, at the end of
                  the track or at the end of the album or playlist, the last track of it found by the tracks to come
                  that are neither queued by hand nor autoplay's (SPTPlayerTrack's provider), or by the next one
                  having played already when it repeats. Over the last seconds (the Live Activity page's Fade out: Off,
                  10 s, 30 s, 1 minute or 2 minutes, 30 s unless picked; at the end of a track, over the whole track
                  when it is shorter) it fades the sound 60 dB through a gain of the mod's own, applied by SpeedPitch.x's notify on the music's RemoteIO unit (never the system
                  volume), and puts the gain back a second after the pause. Spotify's own timer, from the player's
                  ⋯ menu, fades by the same choice and gain (SpotifySleepTimer.m): the core reports it in the player's
                  state (SPTPlayerState's sleepTimer: type 1 at a timestamp, 2 at the end of the track), checked four
                  times a second while Spotify plays; Spotify pauses, the gain is held down from its end until that
                  pause and back a second later, at once on a cancel or a later time. It stands aside while the mod's
                  own timer runs and while Spotify's own Fade out flag (its DuckHandlerImpl's duck) is forced on.
                  Tested on the Mac against harness/sleep-timer/, the gain in the simulator against harness/speed/
    Haptics/      Vibrations (Haptics.h lists its files): a tap of UIKit's feedback generators for the player's and the now
                  playing bar's controls, the scrubber's tenths and ends, cover swipes, gestures and the lyrics page's tap to
                  seek, at the strength set for them (ControlHaptics.x, SGFeedback.m); and Music Haptics, Core Haptics
                  playing along with the song: the music's RemoteIO output unit (SGPlayerMusicOutput, Shared/Player)
                  gets a render notify, the samples, in the unit's output format (the hardware's), go through a drum
                  and bass analyzer on the render thread (SGMusicAnalyzer.m, plain C), and a thread of its own schedules
                  the taps and the rumble for when the sound is heard, at their strength and leaving out what Follows
                  leaves out (MusicHaptics.x). Everything applies at once; nothing plays while Spotify is not the active
                  app. Beside it, In the Background (iOS 18 and up) asks Spotify's extended-metadata for the track's
                  ISRC with Spotify's own spclient headers, asks Apple Music's catalog for that ISRC (the phone's own country first, then the US), and names the
                  matched song's catalog id (same ISRC, length within 2 s, a haptic track) or else the ISRC in the now
                  playing info for iOS's own Music Haptics, which plays on the lock screen and in other apps too
                  (SystemMusicHaptics.x, its pure steps in SGHapticTrack.m). Both may be on: while iOS reports the named song
                  playing, the mod's own stays quiet, since iOS plays the track in front of Spotify too, and also while
                  it asks (10 s at most) and for 3 s after a song is named; with no report by then, once iOS has none,
                  while iOS's is paused in Control Center or in an install iOS does not list, the mod's own plays while
                  Spotify is in front. The analyzer is
                  scored on the Mac against harness/haptics/, as are the pure steps (build/track), the hook, the two
                  switches, the stand-down and the move from the old choice in the simulator against its sim/, the
                  settings against harness/haptics-page/
    AnimatedArtwork/ moving artwork (AnimatedArtwork.h): the track's Canvas, else Apple Music's animated album cover
                  (SGMotionCatalog.m: searched without the album's edition, the edition of the same name first, and
                  left alone for 10 minutes after a 403 or 429; an album's answer kept on disk for a week, so a relaunch skips the search), kept as local files (SGMotionStore.m, a download that
                  fails on the way tried once more), on iOS 26 the lock screen's full-screen
                  artwork (LockScreenMotion.x). With Every song, a song with neither gets its cover over copies of it
                  blurred and swaying, a seamless 8 s 3:4 loop drawn on the CPU only when the lock screen asks for it
                  and kept per picture (SGFluidClip.m). Rendered on the Mac against harness/fluid-clip/. A track whose
                  metadata names no Canvas has it asked of Spotify's Canvas service (MotionSources.m); each track is
                  looked up again when its Canvas comes in a later state, and the next track's clip is fetched ahead
                  (SGMotionFollower.m). The lock screen's clips are Sigma's own, fetched and cut by
                  LockScreenArtwork/ (SGArtworkFile.m: kept in Caches, cut once to 3:4 or 1:1 so the file fits the
                  key as it is; SGAppleArtwork.m: Apple Music's cover by the web player's own token and one catalog
                  search), the follower only deciding when (its `clipFor`); the player's are SGMotionStore.m's. The
                  lock screen takes a clip under a key the system lists, cut to that key's
                  shape when it is not, with its still filled to the size asked (SGMotionClip.m), and a change of the
                  choice applies at once, but to or from Lyrics. The cut and the service's wire format are checked on
                  the Mac against harness/motion/
    LocalFiles/   local files (LocalFiles.h lists its files): Edit info in the player's ⋯ menu, the table's footer
                  under Speed and pitch, which closes the menu and opens a form sheet (the three names, the cover
                  with a menu to change it, Restore file's info; nothing is stored before Save, and a swipe away
                  with changes asks first), storing a title, artist, album and cover by the file's URI and laying them
                  over -[SPTPlayerTrack metadata] and the cover's image request (the redesign's artwork reads the
                  stored cover itself, Redesigned/Kit/SGRBridges.x); the file is never written. Their
                  lyrics are kept under the URI and asked of the sources by name, since Spotify never asks for them;
                  with no source switched on, of LRCLIB alone, which then gets the file's title, artist, album and
                  length. A rename gives a new key (a cover alone does not), asked for at once while the file plays.
                  A miss is asked again a few times, in case it was a lost request. The user's own .lrc files
                  (LocalLyrics.m), imported from Files on the Imported LRC files page under Lyrics' sources and kept
                  as UTF-8 in Documents/Sigma/Lyrics, come before any source: a file linked to the local file
                  playing (Import for current track) is its lyrics whatever its tags say, and any other is matched by
                  [ti:] and [ar:], or a name of "Artist - Title", folded; an import or a delete has the engine forget
                  what it kept for local files and ask again. SGImportedLRCAsk is the same as a source for the
                  order, which moves it on top at the first import and at every link once LyricsSources lists it.
                  Where Spotify's player shows its placeholder for a local file, the file's own cover is found
                  (LocalCover.m) in the image fields of its metadata or, while the titles and artists agree, in the
                  system's now playing artwork, which the lock screen shows; the native look puts it into the front
                  cover's empty image view (Native/LocalFiles/LocalCover.x), the redesign's artwork bridge takes it
                  as the picture of a local file whose metadata names none. A cover picked in Edit info wins.
                  The model and the LRC reading are checked on the Mac against harness/local-files/, the row and
                  the editor in the simulator against its sim/
    AudioEffects/ the audio effects on Spotify's sound (AudioEffects.h has the keys and the page's calls): a render
                  notify on the music's RemoteIO unit (SGPlayerMusicOutput, Shared/Player) runs each finished buffer through the mod's own engine, re-blocked to 1024 frames one block late,
                  in place (AudioEffects.x, SGDSPEngine.m), then hands it, mixed to mono, to one reader that only
                  reads it, switch on or off (SGAudioSetOutputReader: the player's Visualizer). The buffers are in the unit's output format, the
                  hardware's, not the client format Spotify sets. The effects are the SGDSP*.m files, on Accelerate,
                  Apple's Reverb2 unit, libbs2b and EEL2 (vendor/audio). Settings apply as they change, on a queue of
                  its own; the file effects read their files from Documents/Sigma/Audio effects
                  (AudioEffectsFiles.m). Presets and Headphones (AudioEffectsPresets.h lists their files): seven
                  built-in presets over a reset that keep the Graphic EQ, the user's own as a copy of every dsp key, the
                  settings from before the page's first pick saved as one of them, Before presets, and AutoEq's
                  corrections, its INDEX.md fetched from GitHub and cached a month in Caches/Sigma/AutoEq, a
                  headphone's GraphicEQ file put into the Graphic EQ (AutoEq.m), None taking it off; a pick turns the
                  master switch on. A pick can be kept per output (spotifyglass.audioOutputs, by the port's UID): on
                  every AVAudioSessionRouteChangeNotification to another output (AudioEffects.x), a remembered output
                  gets its correction or None, and any other output takes off a correction that came on for one; a
                  pick made with nothing remembered and a curve of the user's own stay, and the master switch is
                  never touched. Checked on the Mac by `harness/audio-effects/build.sh route`.
                  Tested on the Mac against harness/audio-effects/ and harness/autoeq/, the hook in the simulator
                  against its sim/, the page against harness/audio-effects-page/
    HeadGestures/ AirPods gestures (HeadGestures.h lists its files): CMHeadphoneMotionManager's attitudes, while the
                  switch is on and Spotify plays, read for a double nod and a shake, each doing what its pull-down
                  says: Nothing, back or forward 15 s, play or pause (which listens with the song paused too), next or
                  previous track, shuffle, repeat, or Like, which adds the track to Liked Songs through Spotify's
                  collection platform (addURL:showUIConfirmation:completion:); Like and Next track until changed. A
                  tone played through Spotify's playback session confirms each, whatever the Ring/Silent switch says.
                  Try it listens a few seconds and names in its row what it picked up, doing nothing to the song. A
                  sheet teaches one's own nod and shake, five of each after a tone, a ring showing the head live (a dot
                  that moves with it, ticks lighting toward where it went; SGHeadMotionListen) and five dots counting
                  what landed, with Redo last; the threshold kept is the one that fires on all five but one at least, the nod
                  stored before the shakes begin, so Cancel keeps it. Forget shows only while something is learned.
                  The one CMHeadphoneMotionManager is lent to other features
                  (SGHeadMotionListen: Karaoke's spatial voice), and runs for them with the switch off, the detector then
                  unfed. The detector is
                  tested on the Mac against harness/head-gestures/, the hook and the page in the simulator against its sim/
    LiveActivity/ a Live Activity on the lock screen and in the Dynamic Island in one of three views, the line being
                  sung with the next one under it, the tracks up next (a tap on one skipping ahead to it), or a control
                  menu of tabs, Controls (previous, play and pause, next, shuffle, repeat), Queue and a sleep Timer of
                  the mod's own (Player/SleepTimer.m: 15 min, 30 min, 1 hour, End of track, End of album) that fades
                  the sound out and pauses Spotify, and stays set when the card is switched off (LiveActivity.h lists its files): a timer polls the player and
                  sends a new state only when what the view shows changes, local updates only, no push, and asks ActivityKit
                  only then. It ticks four times a second in the lyrics view and once a second in the others. The card
                  is tinted with the cover's color and shows the cover itself, a JPEG of a few dozen pixels inside
                  the state, which ActivityKit caps at 4 KB (the bridge sends it without the cover when it would
                  not fit); the color is darkened to a luminance of 0.04 at most, so the white text keeps 4.5:1 on any
                  cover, and the cover is read only once the now playing title is the new track's. The page's options
                  ride in the state too, read on every tick, so they apply within a tick: the lines' alignment, what the
                  lyrics view shows on a track with no timed lyrics (a note under the track, or the track large), the
                  colors (Spotify's green; Artwork, the cover's color lightened to about the green's luminance in its
                  place; Plain, white on the system's own background), and the progress bar. Artwork off sends no
                  cover at all. The page's preview (SGLiveActivityPreview.m) is a mock of the card in UIKit, not the
                  widget, checked in the simulator against harness/live-activity-page/. Taps are
                  LiveActivityIntents run inside Spotify and take a second or two to show on the card. The widget is extension/LiveActivity; ActivityKit pairs the two
                  by the attributes' type in LiveActivityShared.swift, compiled into both. It starts only with Spotify
                  in front; its settings apply at once. It ends when Spotify is swiped away while running; killed
                  while suspended, Spotify cannot end it, so each state goes stale a minute on (an unchanged card is
                  sent again every 20 s) and a launch ends any left over before it starts a new one. The same folder
                  gives Siri, the Shortcuts app and the Action button Like This Song, Play or Pause, Next and Previous
                  Track, Karaoke and Sleep Timer (AppShortcuts.swift lists them as Spotify's App Shortcuts), and iOS 18
                  controls for Control Center and the lock screen of Like, Karaoke and the sleep timer
                  (extension/LiveActivity/Controls.swift), buttons, as the extension cannot read Karaoke's state. Each is
                  a LiveActivityIntent or AudioPlaybackIntent, so it runs inside Spotify, launched in the background
                  when needed, and LiveActivity.x answers it with the activity on or off, Like through
                  HeadGestures.x's collection platform and Karaoke through SGSetSingOn; the sleep timer (15 min, 30 min,
                  1 hour, End of track, End of album or Off) is the card's own, Player/SleepTimer.m, which keeps its
                  own clock with the activity off. The intent asks again for 8 s while the player is not up,
                  then tells Siri to open Spotify. Checked in the simulator against harness/shortcuts/
    Gestures/     the double tap zones on the player: the grid, what each cell does, the recognizer (each look hooks it on)

Native:

    Appearance/   AMOLED (Amoled.x), the accent colour (Accent.x), the soft top edge (EdgeEffect.x), and Repaint.x, which
                  keeps what the native tweaks stripped transparent
    Navbar/       Spotify's tab bar composed (Navbar.x, NavbarLayout.m, hooked from TabBarHooks.x), the Navbar and Add a tab pages
    NowPlayingBar/ the device button hidden, the bar's flags
    Player/       the full screen player (Player.x), its cards and buttons hidden (PlayerDeclutter.x), the glass lyrics card
                  (LyricsCard.x), the Queue & devices flags
    Lyrics/       the full screen lyrics page on glass (LyricsPage.x)
    Home/         the Home gradient, Home's sections and pills hidden (HomeDeclutter.x), the Home & Library page
    Playlist/     the playlist header and pills, hidden one switch each
    Album/, Artist/ their pages' parts hidden, and the cover or photo behind their headers

Redesigned:

    Kit/          what the redesign builds on (SGRKit.h lists it), the flags it forces (SGRedesign.h, SGRGlassDesign.x for
                  Spotify's own glass design), its repaint hook (SGRRepaint.x), soft top edge, AMOLED black (always on,
                  SGRAmoled.x) and its own accent colour (SGRAccent.x, stored apart from the native look's); and
                  the curtain the playlist, album and artist pages come in behind (SGRReveal.h): black over the
                  whole page from its first pass until the picture, the field's colour, the header with Play and
                  the first track with its text are all in, and then the page fades in from behind it in one
                  go -- the field brightening into the page's colour, the rest fading in where it is, nothing
                  moving -- so it no longer arrives a piece at a time; after 1.2 s it shows whatever is missing, and
                  the back button, being the system's navigation bar, is there throughout
    Navbar/       the glass tab bar (TabBar.x) over its own composition (Navbar.x, NavbarLayout.m) and editor, the glass search field.
                  Spotify is made to leave the glass bar its height where its own bar is shorter (a phone with a home button,
                  Offline or Private Session under the bar), so the now playing bar and the pages move up with it. Under both
                  bars the pages fade to half black (SGRBarFade, the stock bar's own subview). A page scrolled down
                  minimizes the bar to two circles, the first or current tab and the last, with the now playing card
                  between them, and a scroll back up, its top, another tab or the player brings it back
                  (TabBarMinimize.x, MinimizeStep.h; the Player page's Apple Music style). Spotify's container is no
                  UITabBarController, so UIKit's tabBarMinimizeBehavior and bottomAccessory cannot do it. The bars,
                  their circles and the card move as one, on one spring of their own (SGRMotionBar, 0.26 s, no
                  overshoot; at once under Reduce Motion), from what is on screen, so a change turned back half way
                  carries on from there. Each glass tab carries its name for VoiceOver and the large content viewer, labels
                  hidden or not, and the leading circle says it shows all tabs. Laid out on
                  the Mac against harness/tabbar/ (`mini`; a tap on the leading circle `tap`, real flings that turn
                  the bar half way `turns`, a minimize from inside Spotify's own animations `nested`, every frame of
                  the move sampled `motion`), the scroll's steps checked by harness/tabbar/minimize-check.c
    NowPlayingBar/ the glass now playing bar (NowPlayingBar.x), with Spotify's device button on it hidden on request
                  (BarConnect.x, its own key and its own row on the Player page, apart from the native look's), and its like
                  button hidden too (Spotify's own flag ios-feature-nowplayingbar.add_button forced off). The card's text is the Music
                  app's, the title over the artists with no device line, drawn inside Spotify's own text on each swipe page
                  so it slides and fades with it; Spotify lays a page out as "title • artists" over the device line or as
                  title over artists, and both are read. In the minimized row
                  the card drops its device and add buttons, faded out as it heads there and back in as it leaves. Only the title stays in the row. In a Jam the
                  glass stays on the track and Spotify's Jam strip gets a pane of its own above it (harness/tabbar/, jam)
    Player/       the redesigned full screen player (Player.h lists its files), on Spotify Free's units too (a Free
                  account with pick and shuffle gets NowPlayingReinventFreeMode, whose units are classes of their own
                  around the same elements, and each unit hook covers both); its ⋯ opens the system menu, as the ⋯ of every
                  redesigned entity page does (Redesigned/ContextMenu, whose ContextMenu.h says how): a button of the mod's over
                  Spotify's ⋯ takes its touch and opens the menu at touch down, as UIKit opens any button's menu, so it waits on
                  nothing of Spotify's. Share, Add to playlist and Add to queue are a row of three at its top, then
                  PlayerMenu.m's own items (Speed, Pitch & Reverb, and the switches between the Fluid, Animated and
                  Visualizer backgrounds), then More with the rest of Spotify's rows. What is in it and what each row does stay
                  Spotify's: its own sheet is made out of sight, read, and a pick is fired on it; the last complete set of rows
                  is kept across launches, and a pick made before the live rows are in waits up to 4 s for them, else the sheet
                  is shown. A page's ⋯ (playlist, album, artist) opens Spotify's sheet at alpha 0 and the menu over it from an
                  anchor inside the ⋯. Always on in the redesign
                  With Sing on and its voice model downloaded (Mod Settings > Karaoke, Redesigned/Lyrics/SingSettings.m,
                  both applying at once), its microphone (Redesigned/Lyrics/SGRSingControl.m) sits in the
                  lyrics' bottom trailing corner, opposite their glass button, and goes down with the lines when the
                  controls go; while it is open, preparing or explaining itself the controls stay, and a touch on it
                  does not bring them back. What Sing is doing shows on the button, not in words: a ring turning
                  round the microphone while it prepares or recovers, a white fill up to the vocal level while it is
                  on, glass when it is off and a dimmed microphone when it has stopped
    Lyrics/       the full screen lyrics page on glass with Apple Music style lyrics over it, always on (SGRKaraokeView,
                  which the player shows in itself too, Player/PlayerLyrics.x, where after four seconds untouched while
                  the song plays the controls fade out and the lines take the whole player, until a touch or a pause
                  brings the controls back; the tap that does so seeks nowhere): lines sung over each other lit together,
                  the stack moving on once the first is sung out; an instrumental break of 7 s or more held by three dots
                  that breathe and fill over its length on a Core Animation timeline laid against the song's clock; and
                  a line's pronunciation (under the words it spells) and translation, switched on from a glass button in
                  the lyrics' corner that shows only for a song that has them, in the order of sizes the Lyrics page sets
                  (LyricsText.h). Laid out on the Mac against harness/lyrics/
    Home/         Home decluttered to music on black (an allow list of its sections: shortcuts, the DJ without its heading and
                  transcript, the shelves of cards), a large title where the filter pills were with the avatar at the trailing
                  edge, the shelves' headings at the Music app's size, each shortcut tile's cover run across it blurred
                  (SGRPalette's extension), continuous corners on the covers, and in FLEX builds a meter of each scroll's
                  frames and the hooks' time (Home.h lists its files)
    Search/       the Browse page decluttered to its category cards (an allow list of the list's cells: the watch feed
                  carousels and promos collapse, and the cards move up by the spacing they leave), the header the way Home
                  has it without the camera, and each card as Liquid Glass tinted by its own colour, read off the Box's
                  shape layer (Search.h lists its files)
    Library/      Your Library the way Home and Search have their headers: a large title at the leading edge, the avatar
                  at the trailing edge with the search and create buttons before it, the header's scrim gone, each row's
                  artwork at the Kit's radius with a circular one left round, a hairline between the rows, and the search
                  inside the library on glass capsules (Library.h lists its files). The filter chips under the row stay
                  Spotify's: they were taken out when this was first built and put back in 0.21 (issue #20), since
                  sorting a library is not something the page can do without, and Spotify already draws them on the
                  system's own glass
    Playlist/     the playlist page (Liked Songs and one's own too, all three being the same page) the way the Music
                  app lays one out: the cover full bleed across the top dissolving into the page's field with no seam,
                  the title, the creator after their picture and the length centred under it, one row of glass
                  controls (shuffle, a prominent Play capsule taking its glyph and its word from Spotify's own button,
                  add), the find bar and the curation pills gone, and the track rows on the field with a hairline between them
                  (Playlist.h lists its files). Sort and Mix, the two of those pills the ⋯ menu does not already offer,
                  are put on that menu's own sheet instead, above Spotify's rows, and fire Spotify's own buttons.
                  Laid out on the Mac against harness/playlist/
    Album/        the album page laid out the same way, on the page the Creative Work Platform builds rather than the
                  playlist's, so it shares nothing with Playlist/ but the Kit: the cover full bleed dissolving into the
                  field, the title, the artist after their picture and the kind and date centred under it, and the
                  same row of glass controls -- play and shuffle float over the album page outside its header, so they
                  are concealed there and the row carries the Kit's stand-ins, which draw their glyph and fire them. Under the tracks
                  everything the server sends is dropped -- more by the artist, videos, concerts, merch, you might also
                  like, and whatever it adds next -- but the album's own line and its copyright (Album.h lists its
                  files). A podcast's episode page is the same template, so it is given the same field, and what it
                  paints over it is taken off. Laid out on the Mac against harness/album/

App:

    ModSettings.x  the root page and the rows that open it from Spotify's settings and the side drawer
    Pages.m        the Appearance card with Redesigned UI, the Player and Lyrics pages, which Navbar page opens
    About/         the signing warning and the Mod page with the reset
    Onboarding/    the welcome page over Home on the first launch, with Redesigned UI, offered again from the Mod page

Every key a feature stores starts with `spotifyglass.`, whatever it holds: Reset all settings on
the Mod page removes by that prefix and has no list to keep up to date. It leaves `SGKeyStock` behind,
which makes every unset switch read off, so a reset is stock Spotify whatever switches exist.

A hook reads its switch when it runs (`SGEnabled`, `SGHidden`, `SGFlag` from Core/SGPrefs.h), so a
change shows after Spotify restarts; the tab editor on the Navbar page is the exception and applies as soon as the bar lays
out again, as are the Home gradient's colour, strength and height, but not the switch that turns it on, and Vibrations. The root page in `App/ModSettings.x` holds the Appearance card and links the page of each part of Spotify, and only the stored look's.

## Lossless

Off unless `spotifyglass.lossless` is set; there is no settings row yet. A FLAC or ALAC file in Spotify's
Documents/Lossless folder (Files app › Spotify › Lossless) plays in place of Spotify's sound for the same recording.

- **Which file:** the folder's index (`.index.plist`, track URI to file name), else a file whose title tag (or
  name) is the track's title and whose length is within 2 s. Artists are not compared. A file goes in the index
  once its sound matched (`SGLosslessStore.m`).
- **Where in the file:** at each track start, seek and resume, 4 s of Spotify's output are matched against the
  file near Spotify's position: first on a mono copy at 1/16 of the rate, then exactly on a full-rate window. A
  normalized correlation under 0.8 is another recording or master, and Spotify's sound stays. The file plays
  from that frame at the gain that matches Spotify's loudness (`SGLosslessEngine.m`).
- **Playback:** a static 2^19-frame ring that a worker thread fills ahead of where Spotify plays. A block the
  ring does not hold yet keeps Spotify's sound. The swap is in Shared/Player's source selector, before Sing.
- **Data:** Spotify still downloads and decodes its own copy, and it downloads a song as it starts. So while
  the next song in its queue has a file, Spotify's quality is set to low, and the user's value comes back
  afterwards, also at the next launch (`LosslessQuality.x`).
- **Not yet:** Karaoke and speeds other than 1 keep Spotify's sound; the first 4 s after each start, seek or
  resume are Spotify's; a silent block drops the anchor until the next try. Sources that download files are a
  design only: [Lossless sources](lossless-sources.md), [addons](lossless-addons.md),
  [playback investigation](lossless-playback.md), [prototype history](lossless-prototype.md).

## Spicy Lyrics

Spicy Lyrics answers only a key, and its terms want every deployer to have their own, so each user
makes one (16 or older, free):

1. Sign up at developers.spicylyrics.org (email, password, the emailed code).
2. Dashboard, Applications: create an application. Ignore its secret key (`sl_sk_`), which must stay on
   a server.
3. Turn on client access for it and add **No origin header** to the allowed origins (it asks for a
   confirmation). Copy the publishable key, `sl_pk_…`.
4. Mod Settings, Lyrics, Sources: Spicy Lyrics key, paste, Save; tap Spicy Lyrics to put it in the order.

The key is stored under `sigma.spicylyrics.key`, outside the `spotifyglass.` prefix, so no settings
backup, diagnostics dump or reset carries it; only an `sl_pk_` key is taken. A 401 or 403 is shown on
the Sources page ("Key rejected: …", from the error code) and the key is not asked with again for ten
minutes or until it changes; a 429 or 503 is waited out for its Retry-After (or RateLimit-Reset), and
the last request of a window waits out the rest of it. Answers are kept in memory per track only (the
terms allow 30 days). The credit is required: "Apple Music via Spicy Lyrics", "Spotify via Spicy
Lyrics", or for a community sync "Spicy Lyrics, uploaded by …, made by …" with both linked. The
redesign's lyrics show it whatever Show source says, a tap opening the links; the native look puts it
in Spotify's own "Lyrics provided by" line under the lyrics (LyricsHook.x), which
Native/Lyrics/LyricsCredit.x makes tappable. Tested on the Mac against harness/spicylyrics/.

## Make targets

    make build      # out/Sigma-<version>.ipa with FLEX in it
    make release    # the same without FLEX
    make install    # build without FLEX, sign with your certificate, install over USB
    make install FLEX=1   # the same with FLEX, which is what make trees reads through
    make trees      # record view trees screen by screen (FLEX build open on the phone, USB)
    make session    # clean trees, as many snapshots per screen as you like: Enter saves, n goes to the next screen
                    # (SCREENS="playlist artist" for some); every snapshot says whether the mod was at stock
    make log        # stream [spotifyglass] log lines from the phone
    make flags      # regenerate the flag table from the IPA

## Mod Settings

Mod Settings, opened by holding Home on the tab bar or from the first row of the side drawer and the
last row of Spotify's Settings, sorts every
setting by the part of Spotify it changes, so a part's glass, its hide switches and its flags sit on
one page, the mod's own rows first and Spotify's flags below them or on a sub page named after what
they change. It opens on the Appearance card: Redesigned UI, then the stored look's accent colour, and in the native
look AMOLED (the redesign is always black); Spotify's green is offered from the colour row once a colour
is set. Redesigned UI is the one switch between the two looks (see Layers): it glows
(Settings/SGGlowSwitch), its ⓘ says what it changes, and flipping it offers to restart Spotify.
The pages show only what the stored look has: a page opened after flipping the switch already shows
what the restart will bring. In the redesign Karaoke comes next, on a card of its own: Sing's switch and its
voice model's download (Redesigned/Lyrics/SingSettings.m), with Off, On, No model or the download's percentage
beside the row, "Needs iOS 27" below iOS 27. Then a card of parts. Navbar: the tab editor of the stored look,
each with its own list of tabs. Lyrics, beside Player: the ordered list of lyrics sources, lyrics for every track,
naming the source in the redesign, the lock screen, and glass lyrics in the native look; in the redesign also
which of the lyrics, their pronunciation and their translation is set largest, and the translation's language.
Player: Lock screen widget (its controls and, under Artwork, Animated lock screen, the track's Canvas or the album's Apple Music cover played behind the lock screen's controls, on until switched off, with a Sources page for their order, and a "Needs iOS 26" row below that), which work with either look;
in the native look also Now playing bar (its device button and its flags), Queue & devices, and
Spotify's own player screen (artwork background, glass header buttons, Disable Canvas and the sheet,
header, slider and sticky header flags, the cards under the player and the lyrics preview and player
buttons to hide); in the redesign instead, the Player page (Redesigned/Player/PlayerSettings.m), which leads with a card of the
player as the playing track shows on it and a control for the Background behind the player, five of them: Still, the cover blurred and
held still (Kit/SGRField.m's backdrop); Colors, its colours drifting (Kit/SGRFlow.m); Fluid artwork, the default, the cover itself
blurred and slowly turning (Kit/SGRFluid.m, five sliders: Speed, Warp, Blur, Saturation and Brightness, with Reset); the
Visualizer, a calm spectrum of what plays in two soft hills of the cover's colours over Fluid artwork held still (PlayerVisualiser.m,
SGRSpectrum.m: Spotify's output read through the audio effects' notify, 24 bands, drawn at 60 frames a second, 30 behind the lyrics,
stopped in Low Power Mode and with Reduce Motion on), or Animated
artwork, the track's Canvas or the album's Apple Music 3:4 cover looping muted over it (Redesigned/Player/PlayerAnimated.x), the square cover fading out as it fades in and back as it goes, found
the lock screen's way in an order of its own (a Sources page) and falling back to Fluid artwork for a track
without a clip, while one is fetched, while Spotify shows its own music video, and in Low Power Mode or with Reduce Motion on; the
choice: Fluid, Animated and the Visualizer share the Fluid field, so a change between them applies at once, while Still and Colors are made once a
launch and apply after a restart; the rows under the card follow the choice: Fluid's sliders (the Visualizer and Animated artwork take its
look where they show Fluid), Animated artwork's Sources; the card's own clip preview is not drawn, the clip playing in the player; laid out against harness/kawarp/, the player's side against harness/player/ (its fluid and
animated scenarios). Then a Controls card: Volume (on until switched off; PlayerVolume.m), the system's slider under the controls for this iPhone or the Connect device's, and
Follow the cover (off until switched on; PlayerCoverAccent.x), which paints Spotify's lit like, shuffle and repeat in the most colourful of the cover's
five colours instead of the accent, once per cover, a grey cover giving the accent back: Spotify bakes the accent into those controls' images, backgrounds and
Lottie shapes, so the player recolours each of them itself over its bottom stack whenever the colour or a button changes. Then Vibrations under either look, a card for
Controls (on until switched off) and one for Music Haptics (off until switched on, with an ⓘ saying it
follows the sound this iPhone plays while Spotify is open), each opening out while its switch is on:
Controls into its Strength (10 to 100%, a tap at the new strength with each step), Music Haptics into its
Strength (20 to 200%, 100% being how it first shipped) and Follows, Everything (a tap on each kick and
snare and a rumble under the bass), Beat (the taps without the rumble) or Bass (the kicks' taps and the
rumble), all applying straight away. Home & Library, in the native look only:
the Gradient page (the wash behind the top of Home in one of eight colours, at three strengths and
four heights) and the Home flags, the parts of Home to hide including the DJ button and badge, the
playlist header, buttons and pills to hide, and the Library flags. Then Privacy & clutter
(Block telemetry; hiding the video carousel and social proof in Search, and a Tips page under them,
every switch there forcing a flag Spotify ships on to off; then what the telemetry blocking has stopped). Last, All flags, Spotify's remote-config flags with a search field and an
Auto / Off / On control per flag (a text field for the number and text ones), and Mod: the
build and Spotify's version, the welcome tour again and Reset all
settings. A flag switch on a page forces that one flag and off leaves Spotify's own value, so the All
flags page is where a flag goes back to Auto. Spotify ships its newer design behind several flags at
once, and the redesign is built on it (the glass navigation bar, the new player slider, the sheet style
player, the queue and Connect sheets, the redesigned player header, the sleep timer's options sheet):
while Redesigned UI is on each is forced, over an override too, and their rows elsewhere show what is
forced and take no touch. `Redesigned/Kit/SGRGlassDesign.x` holds the list; what else forces a flag
registers in `Core/SGFlagForce.h`. A change shows after Spotify restarts.

The tab editor on the Navbar page is the exception and applies as soon as the bar lays out again. It lists the tabs in the order
the bar shows them: drag to reorder, tap to hide or show, and Add a tab opens a sheet that puts a page
of Spotify's or any `spotify:` link on the bar under a name of your own, with one of Encore's own glyphs
or an SF Symbol (the names come from `Core/SGSFSymbolCatalog.m`, MIT). Spotify's own tabs are kept by the
name under their icon, so they can be hidden but never removed, and switching the app's language
starts the order over. A tab of the mod's own opens its link through Spotify's link dispatcher, onto
the stack of the tab you are on. The redesign's glass bar lights it while that page is on the stack and
a second tap goes back to it; the native bar leaves the tab you were on lit. Hide labels, on the same page, leaves the glass bar with its
icons alone and applies straight away too.

## Adding a feature

1. `make trees`, record the screen, read `trees/<screen>.txt` for the classes and frames.
2. Decide the layer (see Layers), then make `tweak/Sources/<Layer>/<Feature>/` with `<Feature>.h` declaring the switch key
   (`#define SGKey<Feature> @"spotifyglass.<feature>"`) and `UIViewController *SG<Feature>SettingsPage(void)`.
3. Add the hooks in `<Screen>.x`: `#import "Core/SGCore.h"` and the feature header, guard on the
   switch, use `SGGlassFor`/`SGGlassAt` + `SGShapeGlass` for glass and `SGStripBackgrounds` to clear
   Spotify's paint, and end with `%ctor { %init; SGRequireClasses(@[...]); }`, gated first on the layer's look
   (`SGNativeUI()` or `SGRedesignedUI()`) in Native/ and Redesigned/.
4. Add `<Feature>Settings.m` returning an `SGModPage` of `SGSection`s of `SGSwitchRow`/`SGHideRow`/
   `SGFlagRow`/`SGChoiceRow`/`SGSliderRow` (Settings/SGModPage.h), and put it on the page of the part of
   Spotify it changes in `App/Pages.m` or `App/ModSettings.x`.
5. `make install`. Log lines are prefixed `[spotifyglass]`. A FLEX build serves the visible screen's
   tree on the phone's port 8085, which `make trees` reaches over USB through iproxy.

A class Spotify has renamed shows up in the log as `class X not found, its hooks are inactive`;
declare the classes a feature needs in `Headers/` only when a hook calls into them by type.
