# The timeline as a multi-track audio mixer

The timeline sums an unbounded number of audio lanes through one
`AVMutableAudioMix`, built once in `CompositionBuilder.buildVisuals` and shared
by playback, scrub preview, and export. This doc records what makes it a usable
mixer today and specs the work that would make it a full one.

## Shipped — the "cheap" tier

Everything here rides the existing `AVMutableAudioMixInputParameters` volume
ramps, so it applies identically in preview, the master meter (fed through the
same mix), and every export path.

- **Per-lane gain fader.** `Track.gain` (linear, 1.0 = 0 dB) folds into each
  clip's volume ramp in `CompositionBuilder.buildVisuals` (`laneGain`). Range
  −∞…+15 dB via `VolumeScale`. A horizontal fader is drawn on the lower line of
  each audio lane header (`TimelineHeaderView.drawGainFader`) when the row is
  ≥ 44 pt tall; drag to set, double-click to reset to 0 dB. Live drag goes
  through `setTrackGainLive` (coalesced preview refresh); the drag commits one
  undo step via `commitTrackGain`.
- **Solo.** `Track.soloed` + `Timeline.trackIsAudible`: a mute always silences;
  once any lane is soloed, only soloed lanes play. Header button next to mute
  (orange when active). Nested/sequence audio obeys the same rule via its
  parent track.
- **Mute** (pre-existing) and **per-clip** volume / fades / dB keyframe
  automation / denoise (pre-existing) are unchanged and compose with lane gain.

Known gap: FCPXML export (`XMLExporter`) emits per-clip volume but **not** lane
gain or solo state — an interchange-fidelity gap, not a render gap (baked video
exports are correct because they use the shared `audioMix`).

## Spec — the "expensive" tier

These do **not** fit `AVMutableAudioMix`, whose per-input parameters are
volume-ramp only (no pan, no per-input tap, no post-sum bus). They require
replacing — or tapping — the audio path. Playback today is a single `AVPlayer`
with `item.audioMix`; there is no `AVAudioEngine` in the playback path (only the
scrub engine has one).

### 1. Pan (L/R) — model + real-time processing

`AVMutableAudioMixInputParameters` cannot pan. Two routes:

- **`MTAudioProcessingTap` per audio input** on the `AVPlayerItem`'s mix. Attach
  a tap to each input's parameters; the tap's process callback applies a
  constant-power pan matrix (and would also be where a per-lane meter tap lives,
  see §3). Keeps the `AVPlayer` playback architecture. Complexity: C callback
  bridging, manual channel handling, tap lifecycle across `replaceCurrentItem`
  rebuilds.
- **`AVAudioEngine` graph** replacing `AVPlayer` audio: one
  `AVAudioPlayerNode`/source per lane → per-lane `AVAudioMixerNode` (has `.pan`)
  → master mixer. Cleaner mixer semantics, but decouples audio from the
  `AVPlayer` used for video, so A/V sync becomes our problem (sample-accurate
  clock sharing, seek/scrub coordination). Larger blast radius.

Model: add `Track.pan: Double` (−1…+1). Persist + Codable default 0 (mirror the
`gain`/`soloed` roundtrip). No export change if the tap is attached in the
shared builder; the `AVAudioEngine` route needs an offline render path for
export (see §4).

### 2. Master bus fader

A single post-sum gain stage. Trivial in the `AVAudioEngine` route
(`engine.mainMixerNode.outputVolume` + a stored `Timeline.masterGain`).
In the `AVPlayer` route there is no post-sum node, so it's either `player.volume`
(output-only, not baked into export) or a master `MTAudioProcessingTap` on a
summed input — meaning you already need the tap infrastructure from §1/§3.
Recommendation: master fader lands naturally once §1 picks the engine route;
until then it's a half-measure.

### 3. Real metering — per-lane + true master tap

Today's meter (`AudioMeter` / `AudioMeterView`, "Master Audio Meter") is a
**peak** meter fed by a *parallel offline re-decode* in `ScrubAudioEngine`
(`AVAssetReaderAudioMixOutput`), sampled ~once per frame around the playhead via
`VideoEngine`'s time observer. It honors the mix (same `audioMix`) but is an
approximation, master-only, and misses sub-frame peaks. There is no
`installTap`/`MTAudioProcessingTap` anywhere.

Target:

- **Per-lane meters** in each lane header, plus the master.
- **Live tap** on the actual output, not a re-decode: `MTAudioProcessingTap` per
  input (lane meters) and one on the summed output (master), or `installTap` on
  each `AVAudioMixerNode` in the engine route.
- Add **RMS/VU** alongside peak (`AudioMeter` computes peak via `vDSP_maxmgv`
  only today); a mixer wants both.
- Meter state is already `@Observable` (`AudioMeterHub`); generalize from a
  single hub to per-lane hubs keyed by track id.

### 4. Export parity

The `AVPlayer` + `MTAudioProcessingTap` route keeps export working unchanged
(the tap is attached to the same shared `audioMix` the export session reads).
The `AVAudioEngine` route does **not** — `AVAssetExportSession` won't run an
engine graph, so pan/master/effects would need an **offline `AVAudioEngine`
manual-rendering** pass (`enableManualRenderingMode`) writing via
`AVAssetWriter`, replacing the export audio path. This is the single biggest
reason to prefer the tap route unless we also want an effects graph (EQ,
compression) — which the engine route gives nearly for free via `AVAudioUnit`
nodes.

### Recommended sequence

1. Pan via **`MTAudioProcessingTap`** on the existing `AVPlayer` mix (keeps
   export + A/V sync free) → `Track.pan`.
2. Per-lane + master meter taps reusing the same tap plumbing → retire the
   re-decode meter.
3. Master fader on a summed-output tap.
4. Only if EQ/compression/an effects graph is wanted, migrate to
   `AVAudioEngine` + offline export render — a deliberate, separate project.
