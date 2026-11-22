# Hud — "gece sürüşü" design system

API reference for porting screens. Spec: `docs/DESIGN.md`. Source of truth:
`docs/design/crenel-prototype.html` (CSS class / sprite id given in the right column).
Gallery renders: `touch /tmp/CrenelExportUIAudit`, run `HudFoundationGalleryTests`,
look in `artifacts/ui-audit/foundation/`.

Files: `HudTokens` · `HudSVGPath` · `HudIcons` · `HudLamps` · `HudButtons` ·
`HudComponents` · `HudSegmentDigits` · `HudGauge` · `HudInstruments` · `HudScales`.
`Crenel*` files are legacy and resolve to `Hud` values; do not use them in new code.

## Rules that are easy to get wrong

- One hero number per surface in `HudSegmentDigits`; everything else is Geist via `.hud(_:)`.
- State is a **shape** (`HudStatusShape`), colour is only severity. Lamps are for calm
  states (ready, connected, live, selected). Never coloured status text: use `HudStatusWord`.
- No dividers. No uppercase, no widened tracking.
- Actions end at the trailing edge: danger · secondary · primary. At most one primary per
  surface, always with its keycap (`esc` on cancel, `↩` on primary).
- Glow radii: the prototype's `drop-shadow(0 0 Npx)` → `.shadow(radius: N)`;
  `box-shadow` / `text-shadow` `0 0 Npx` → `.shadow(radius: N / 2)`.
- On desktop layers call `.hudSurface(Hud.Layer.sidebar / .window / .sheet)` so icon
  cut-outs (mic-off slash, badges, face rings) use the right colour. Default is black.
- All loops (`hudLoop`, `HudBusy`, `HudScanner`, `HudCaret`, ignition, lamp fire) already
  respect Reduce Motion.

## Measure model (`Hud.Layout`, C13)

Every gap is a visible gap. Text: `hudTrimmed(style)` (cap height to baseline). Glyphs:
lay out by ink (`.padding(-Hud.Layout.glyphInset)` on a 16 pt glyph). Rhythm: pair 7,
block 16, item 20, label → group 20, section 28, edge 20. Rows: `.hudRow(.icon)` (10 all
round) or `.hudRow(.tile)` + `.hudGlide(…)` + `.hudTileOutset()` (4 around the 56 × 36
tile, 10 at the trailing value, rows 4 apart). Section labels: `HudGroupHeader(title:
count: rows:)` renders "Name · n"; the gap above the next label is `kind.sectionGap`.
Hover slab radius 10, field 34. Spec: `docs/DESIGN.md` › Ölçü modeli.

## Tokens (`HudTokens.swift`)

| Swift | Value | Prototype |
| --- | --- | --- |
| `Hud.Ink.ink1…ink5` (`text1…text4` = legacy aliases) | `#f3f1ec #aaa7a1 #76736e #4c4a47 #2e2d2b` | `ink-1…5` |
| `Hud.Ink.hover / field / fieldFocus / quiet / selected / track` | white 5.5 / 5.5 / 9 / 7 / 10 / 8 % | slab, field, quiet button, selected |
| `Hud.Ink.signal / live / ok / mark` | `#ffad33 #ff5a47 #34e6cb #14f0d4` | `signal`, `live`, `ok`, mark teal |
| `Hud.Ink.danger / onKey / ghostWord` | `#ff6b59 #0b0b0a #3a3936` | danger ink, primary key ink, unlit annun word |
| `Hud.LampColor` `.amber .red .teal .white .dim .off` (`.color`, `.core`, `.glow`) | lamp colours + hot cores | `.lamp.on-a/-r/-g/-w/-d` |
| `Hud.Layer.sidebar / window / sheet / wellTop / wellBottom` | `#080807 #0e0e0d #121211 #050505 #0a0a09` | `.sidebar`, `.win`, `.sheet`, `.well` |
| `Hud.Style` `.hero .title .body .label .meta .micro .unit .read .page` | 17/600 −.012em · 15/600 −.006em · 13/500 · 12.5/500 · 11.5/400 ink3 · 10/500 ink4 · 11/500 ink3 · 13/400 line 1.6 · 22/600 −.02em | `.t-hero … .t-read`, `.unit` |
| `Hud.font(size, weight)` | Geist at any size | — |
| `Hud.Radius` `.lamp 2 .key 4 .xs 6 .s 7 .control 8 .l 9 .row 10 .well 12 .console 13 .sheet 14 .panel 16` | | |
| `Hud.Row` `.twoLine 50 .oneLine 48 .task 38 .groupHeader 28 .timeColumn 42 .inset 10 .gap 12` | | `.row .row-1 .trow .group-h .tcol` |
| `Hud.Notch` `.cameraGap 186 .compactHeight 32 .stripWidth 440 .stripHeight 38 .openWidth 560 .openInset 14 .bandHeight 32 .topRadius .bottomRadius .lean .earTitleMax 118` | | `#notch .ears .peek .strip .band` |
| `Hud.Window` `.size 1240×760 .sidebarWidth 224 .toolbarHeight 60 .settingsRailWidth 200 .meetingListWidth 300 .detailRailWidth 232` | | desktop |
| `Hud.Size` | legacy (`panelWidth` is still 490 — the notch port switches to `Hud.Notch.openWidth`) | |

Motion (`Hud.Motion`): `.shape` 0.52 s (.3,1.16,.4,1) · `.content` 0.18 s after 0.115 s ·
`.slab` 0.18 s (.2,.8,.2,1) · `.tabLamp` 0.32 s (.3,1.25,.4,1) · `.railLamp` 0.34 s
(.3,1.2,.4,1) · `.rowSlide` 0.38 s (.3,1.08,.4,1) · `.enter` 0.32 s (.2,.8,.2,1),
`enterOffset` −5, `staggerBase` 40 ms, `staggerStep` 28 ms · `.igniteUp` 0.42 s /
`.igniteDown` 0.52 s · `.hover` 0.15 s · `.toggle` 0.2 s · `.card` 0.22 s · `leanDelay`
0.18 · `lampSequence` 0.42 · `stripDismiss` 8 / `insertedDismiss` 3 · periods: pulse 1.4,
breathe 1.8, blink 1.1, busy 1.05, caret 1, scan 1.6, `peakHold` 0.7. Legacy: `.glide`
(= slab), `.morph` (= shape), `.change`.

View modifiers:

```swift
Text("Design review").hud(.hero)                 // font + tracking + default ink; .hud(.meta, Hud.Ink.ink2) overrides
view.hudGlow(color, tight: 2, tightOpacity: 0.6, wide: 7, wideOpacity: 0.22, enabled: true)  // two-layer bloom
view.hudBleed(Hud.Ink.live)                      // `.bleed` radial spill behind a readout
view.hudSurface(Hud.Layer.sidebar)               // `--surface`
section.hudStagger(index, shown: appeared, reduceMotion: reduceMotion)   // `[data-stagger]`
view.hudLoop(.pulse | .breathe | .blink)         // `.pulse .breathe .blink`
Color(hud: 0xF3F1EC)
```

## Icons (`HudIcons.swift`)

```swift
HudIcon(_ glyph: HudGlyph, size: CGFloat = 14, solid: Bool = false, badge: HudGlyphBadge? = nil)
HudIcon(.mic)                                             // i-mic, takes .foregroundStyle
HudIcon(.tape, size: 16, solid: isSelected)               // f-tape when lit / selected
```

`HudGlyph`: calendar, queue, mic, micOff, speaker, video, window, pin, history, tape,
repeats, record, stop, chevronRight/Left/Down, arrowRight, plus, close, spark, link, bell,
place, transcript, sliders, shield, warning, people, keyboard, edit, copy, trash, more,
play, pause, waveform, search, archive, accessibility, sun, gauge, clock, globe, share
(`i-*`). Solid forms (`f-*`, `glyph.hasSolid`): calendar, queue, mic, micOff, speaker,
video, tape, transcript, spark, keyboard, accessibility, gauge, waveform, sliders, sun,
archive, warning, bell, shield. Sizes: 16 `.ico`, 14 `.ico-s`, 12 `.ico-xs`.
`HudGlyphBadge`: `.bang`, `.x` (`mod-bang`, `mod-x`).

| Swift | Prototype |
| --- | --- |
| `HudMark(width: 15, color: Hud.Ink.mark, glow: 2.5)` | `i-mark`; `HudMark(width: 46, glow: 6)` on the onboarding gauge |
| `HudAppTile(size: 26)` | `.app-tile` |
| `HudBrand()` | `.nb` (mark + "Crenel" in the open band) |
| `HudLogo(size: 24)` | `i-logo` |
| `HudStateMark(state: TaskStatus, size: 16)` | `m-open / m-progress / m-blocked / m-done` |
| `HudPriorityBars(level: 0...3, tint:)` | `.pri` |
| `HudSVGPath.path("M8 1L15.25 14H.75Z")` | port any other sprite path |

## Lamps, status, telltales (`HudLamps.swift`)

```swift
HudLamp(_ color: Hud.LampColor, form: .bar | .dot = .bar, loop: HudLoop = .steady, fires: Bool = false)
HudLamp(.teal)                                   // `.lamp.on-g`
HudLamp(.red, form: .dot, loop: .pulse)          // `.lamp.dot.on-r.pulse` (recording)
HudLamp(.amber, loop: .blink)                    // waiting
HudLamp(granted ? .teal : .off, fires: true)     // `.lamp.fire` when it turns on

HudCells(done: 1, total: 5)                      // `.cells` (i.on)
HudCells(states: [.done, .current, .off, .off])  // processing ear (`done`, `cur`)

HudStatusShape(_ status: HudStatus, size: CGFloat = 12, tint: Color? = nil, loop: HudLoop = .steady)
HudStatusShape(.warn)                            // `data-sg="warn"`; .err .warn .off .wait .stop .busy
HudStatusShape(.off, size: HudStatusShape.ear, tint: Hud.Ink.live)   // sizes .row 12 / .ear 14 / .hero 24
HudBusy()                                        // `.busy`
HudStatusWell(.err)                              // `.sg-hero` 44 pt well with a 24 pt shape
HudStatusWord(.ok, "Connected")                  // `.ok-t`; .dim .warn .err .off() .off(blocking: true)

HudTelltale(_ glyph, _ state: Hud.LampColor, paren: Bool = false, badge: HudGlyphBadge? = nil, size: CGFloat = 16, loop:)
HudTelltale(.mic, .white)                        // `data-tt="mic" data-st="w"`
HudTelltale(.mic, .amber, paren: true)           // `data-paren` (24×16)
HudTelltale(.speaker, .red, badge: .bang)        // `data-mod="bang"`
HudTelltale(.calendar, .off)                     // unlit ghost; use size: 14 in the ears
HudTelltaleTile(.warning, .red, size: 18)        // `.ttile` (16 in the ears)
```

`HudPulse(color:)` is legacy (a pulsing dot lamp).

## Buttons (`HudButtons.swift`)

```swift
HudButtonStyle(kind: .primary | .secondary | .danger | .ghost | .icon | .iconFramed, size: .large | .regular | .small | .mini, isOn: false)
HudButton("Join", key: "⌘J", kind: .primary, size: .small) { }          // `.btn-primary.sm` + `.kbd`
HudButton("Record", lamp: .red, key: "⌘R", size: .small) { }            // `.btn-secondary.sm`
HudButton("Clear", glyph: .trash, kind: .danger, size: .small) { }      // `.btn-danger`
HudButton("Export", glyph: .share, trailingGlyph: .chevronDown) { }
HudButton("Rename", kind: .ghost) { }                                   // `.btn-ghost`
Button { } label: { HudButtonLabel("Add", glyph: .plus) }.buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))  // `.btn.xs`
HudIconButton(.tape, isOn: true, help: "Recordings") { }                // `.btn-icon(.on)`
HudIconButton(.more, framed: true, small: true) { }                     // `.btn-icon.framed.sm`
HudKeycap("esc")                                                        // `.kbd` (adapts inside a primary key)
HudKnob(.mic, lamp: .white, help: "Meeting mic on") { }                 // `.knob` + lamp; small: true → `.knob.sm`
HudKnob(.stop, tint: Hud.Ink.live) { }
HudActions { HudLamp(.teal); Text("Synced with Reminders") } buttons: { HudButton(…) }   // `.actions` + `.note`
HudActions { HudButton(…) }                                             // buttons only (`.actions.justify-end`)
HudConsole { HudLamp(.teal); Text("…") } buttons: { … }                 // `.console`; height: 52 for the recovery bar
```

Sizes lg 32 / regular 28 / sm 26 / xs 22. Disabled (`.dis`) = `.disabled(true)` → 40 %.
`HudKeyFace(kind:radius:isHovering:isPressed:)` is the key body if you need it elsewhere
(tray). Add `.keyboardShortcut` yourself; the keycap is only the print.

## Components (`HudComponents.swift`)

| Swift | Prototype |
| --- | --- |
| `HudTabs(items: [.init(tab:, title:, badge:)], selection: $tab)` | `.tabs` + `.tab-lamp` |
| `HudRail(items: [.init(value:, glyph:, title:, readout:, lamp:)], selection: $page)` | `.rail` + `.rail-lamp` + `.sb-item` |
| `HudRow(.twoLine / .oneLine / .task) { … }` | `.row` / `.row-1` / `.trow` |
| `HudTimeColumn("16:00", "48:12", dim: false)` | `.tcol` |
| `.hudGlide(id, hovered: $hovered, in: namespace, forced:)` | `.slab` (one sliding hover slab per list) |
| `HudGroupHeader(title: "Today", count: 3)` / `HudGroupHeader(title: "Today") { HudCells(done: 1, total: 5) }` | `.group-h` + `.n` |
| `Toggle(…).toggleStyle(HudToggleStyle())` / `HudSwitch(isOn:)` | `.toggle` |
| `HudSelect(selection: $v, options: [(v, "Forever")])` / `Menu{}.menuStyle(.button).buttonStyle(HudSelectStyle())` | `.select` |
| `HudTextField(text: $t, prompt: "Name")` / `.hudField(height: 44, radius: 12, isFocused:, padding: 10)` | `.sfield` / task input |
| `HudSearchField(text: $q)` | `.search` |
| `HudChip("Today 15:00", lamp: .amber)` · `HudChip("Tomorrow", glyph: .plus, style: .outline)` · `HudChip("48 min", glyph: .clock, style: .tag)` · `HudChip("High") { HudPriorityBars(level: 3) }` | `.chip` · `.chip-out` · `.chip-s` |
| `HudSegmented(items: [(v, "All")], selection: $v) { leading($0) }` | `.seg-ctl` |
| `Button("Today") {}.buttonStyle(HudPillStyle(isOn: true))` | `.pill(.on)` |
| `HudAnnunciator(items: [.init(v, "Needs you", count: 2)], selection: $v)` | `.annun` |
| `HudFrame("Details") { … }` | `.frame` |
| `.hudWell(radius: 12)` + `HudWellDivider()` | `.well` |
| `.hudPanel(radius: 16, isHovering:)` | `.panel`, `.tile` |
| `.hudSheet()` | `.sheet` |
| `.hudGroupCard()` | `.sgroup` |
| `.hudStrip()` | `.strip` |
| `HudFaces(initials: ["D", "E", "+1"])` | `.faces` |
| `HudBigKeycap("fn", glyph: .globe, lamp: .teal)` | `.keycap` |
| `HudIconTile(.spark)` | `.ph-icon` |
| `HudCaret()` | `.caret` |
| `HudSpinner()` | `.spin` |
| `HudEarsLayout(gap:padding:)`, `HudFormat`, `HudSegmentMeter`, `HudLevelMeter` | legacy helpers, kept |

Context menus and alerts are native (not styled).

## Instruments

```swift
// Segment numerals — `.segd` (HudSegmentDigits.swift)
HudSegmentDigits(_ text: String, height: CGFloat = 13, cells: Int = 0, color: Color = ink1, glows: Bool = true)
HudSegmentDigits("12:48", height: 34)                         // 13 ear · 24 hero · 34 recording; chars 0-9 : . - space
HudSegmentDigits("8", height: 24, cells: 2, color: Hud.Ink.signal)   // `data-cells`: leading ghost 8s
HudReadout("33", unit: "min", height: 13, cells: 2, color:)   // digits + `.unit`

// Tick gauge — `.gauge` / `.gauge-box.bleed` / `.gauge-c` (HudGauge.swift)
HudGauge(value: 0…1, ticks: 60, major: 15, size: 104, tint:, zones: [HudGaugeZone], labels: [String]?, bleed: true,
         ignite: false, igniteTrigger: AnyHashable?) { centre content }
HudGauge(value: 0.55, zones: HudGaugeZone.countdown) {        // `data-zones="0-10:a|0-2:r"`
    HudSegmentDigits("33", height: 24, cells: 2); Text("min").hud(.micro, Hud.Ink.ink3)
}
HudGauge(value: 0.133, tint: Hud.Ink.signal, zones: HudGaugeZone.redline) { … }      // `0-2:r`
HudGauge(value: 0.55, size: 148, zones: HudGaugeZone.countdown, labels: ["0", "15", "30", "45", "60"], ignite: true) { … }
HudGauge(value: 1, ticks: 90, size: 220, ignite: true) { HudMark(width: 46, glow: 6); … }   // onboarding welcome
HudRestingGauge()                                             // empty state, `--:--`
HudRestingGauge(status: .err | .off)                          // shape instead of `--:--`
HudGaugeFace(value:…)                                         // the bare, animatable face
```

Ignition (`ignite: true`) sweeps 0 → full (0.42 s) → value (0.52 s) on appear; pass it only
when the panel opens from closed / a desktop page changes. `igniteTrigger` re-runs it.

```swift
// HudScales.swift
HudDayRuler(span: 8...20, now: 10.7, events: [.init(14.5, 15.25, .focus), .init(17.5, 18, .invite)], wide: false)   // `.ruler`
//   kinds: .normal .focus .amber .invite .dim; wide: true prints `title:` under blocks (`.ruler.wide`, 62 pt).
//   No built-in margin: the notch ruler takes `.padding(.horizontal, 10)`.
HudRamp(elapsed: 768, plan: 3600, scaleMax: nil, width: 196)  // `.ramp`; put Text("of 60 min").hud(.micro) beside it
HudTunerScale(minutes: 48)                                    // `.tuner`
HudWaveform(samples: [0…1], progress: 0.25, headOverhang: (2, 9), height: 28) { position = $0 }   // `data-wave` + `data-head`
//   desktop player: headOverhang: (4, 4). HudWaveform.demoSamples() = the prototype's bars.
HudSchematic(lit: [.notifications, .speakers, .fnKey, .cursor], scanning: false)   // `.schem`

// HudInstruments.swift
HudFuse(fraction: 0.55, color: ink1, cornerInset: 10)         // `#fuse`; overlay at the notch's bottom edge
HudVUMeter(level: 0…1, cells: 30, isOff: false, peak: nil, ignite: false)   // `.vu` (peak hold built in), `.vu.off`
HudLadder(level: 0…1, columns: 6, quiet: false, tint:)        // `.ladder`; or HudLadder(levels: [Double])
HudChartRecorder(samples: [0…1])                              // `.chart`; newest sample last
view.hudScanner(active, radius: 10)  /  HudScanner()          // `.scanner`
HudLEDStack(lit: 5, cells: 8, tone: .today | .past, small: false)   // `.stack`, `.stack.dim`, `.stack.sm`
HudDotMatrix(value: 0.64, count: 78, mark: 0.46)              // `.dots` + `.dots-mark`
HudCapsules(done: 1, underWay: 1, total: 5)                   // `.caps`
HudCapacityScale(level:, cells: 24, minLabel: "−60", maxLabel: "0 dB", glyph: .mic, isOff: false)   // `.cap` + `.zstrip`
HudStations(titles: ["Saved", "Uploading", "Transcript", "Notes"], current: 1)       // processing rail
HudTalkBar(shares: [0.46, 0.38, 0.16]) + HudSpeakerDot(index:) // notch talk-time bar + legend
HudTrack(value: 0.46, tint:, glows:)                          // `.track`
HudLane(segments: [(share, speakerIndex)])                    // `.lane`
```

## Not in the foundation (screen work)

The notch shape and its three sizes, the band layout, the strip's streaming text mask,
the task row tray slide (`Hud.Motion.rowSlide`, `HudKeyFace`, `HudStateMark` are the
parts), the task card, toolbar and sidebar layout. Tokens for all of them are above.
