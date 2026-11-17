import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

/// The "gece sürüşü" design-system foundation: geometry checks plus an offscreen gallery
/// of every component and instrument on black. PNGs are written to
/// `artifacts/ui-audit/foundation/` when `/tmp/MeetingNotchExportUIAudit` exists, to be
/// compared against the prototype (`docs/design/crenel-prototype.html`).
@MainActor
final class HudFoundationGalleryTests: XCTestCase {
    // MARK: Geometry and tokens

    func testInkAndLampTokensMatchTheSpec() {
        XCTAssertEqual(hex(Hud.Ink.ink1), "F3F1EC")
        XCTAssertEqual(hex(Hud.Ink.ink2), "AAA7A1")
        XCTAssertEqual(hex(Hud.Ink.ink3), "76736E")
        XCTAssertEqual(hex(Hud.Ink.ink4), "4C4A47")
        XCTAssertEqual(hex(Hud.Ink.ink5), "2E2D2B")
        XCTAssertEqual(hex(Hud.LampColor.amber.color), "FFAD33")
        XCTAssertEqual(hex(Hud.LampColor.red.color), "FF5A47")
        XCTAssertEqual(hex(Hud.LampColor.teal.color), "34E6CB")
        XCTAssertEqual(hex(Hud.LampColor.white.color), "F3F1EC")
        XCTAssertEqual(hex(Hud.LampColor.amber.core), "FFE2B3")
        XCTAssertEqual(hex(Hud.Layer.sidebar), "080807")
        XCTAssertEqual(hex(Hud.Layer.window), "0E0E0D")
        XCTAssertEqual(hex(Hud.Layer.sheet), "121211")
        XCTAssertEqual(alpha(Hud.Ink.hover), 0.055, accuracy: 0.001)
        XCTAssertEqual(alpha(Hud.Ink.field), 0.055, accuracy: 0.001)
        XCTAssertEqual(alpha(Hud.Ink.quiet), 0.07, accuracy: 0.001)
        XCTAssertEqual(alpha(Hud.Ink.selected), 0.10, accuracy: 0.001)
    }

    func testTypeStylesMatchTheSpec() {
        let table: [(Hud.Style, CGFloat, Hud.Weight, CGFloat)] = [
            (.hero, 17, .semibold, -0.204), (.title, 15, .semibold, -0.09), (.body, 13, .medium, 0),
            (.label, 12.5, .medium, 0), (.meta, 11.5, .regular, 0), (.micro, 10, .medium, 0),
            (.unit, 11, .medium, 0), (.read, 13, .regular, 0)
        ]
        for (style, size, weight, tracking) in table {
            XCTAssertEqual(style.size, size)
            XCTAssertEqual(style.weight, weight)
            XCTAssertEqual(style.tracking, tracking, accuracy: 0.0001)
        }
        XCTAssertEqual(hex(Hud.Style.meta.defaultColor), "76736E")
        XCTAssertEqual(hex(Hud.Style.micro.defaultColor), "4C4A47")
        XCTAssertEqual(hex(Hud.Style.unit.defaultColor), "76736E")
    }

    func testEveryGlyphHasLineArtAndLitGlyphsHaveSolidArt() {
        for glyph in HudGlyph.allCases {
            let layers = try? XCTUnwrap(HudGlyphArt.line[glyph], "no line art for \(glyph)")
            XCTAssertFalse(layers?.isEmpty ?? true)
            for layer in layers ?? [] {
                let box = layer.path.boundingRect
                XCTAssertFalse(box.isEmpty && box.width == 0 && box.height == 0, "\(glyph) has an empty layer")
                XCTAssertTrue(CGRect(x: -0.01, y: -0.01, width: 16.02, height: 16.02).contains(box), "\(glyph) leaves the 16 grid: \(box)")
            }
        }
        let solid: Set<HudGlyph> = [.calendar, .queue, .mic, .micOff, .speaker, .video, .tape, .transcript, .spark, .keyboard,
                                    .accessibility, .gauge, .waveform, .sliders, .sun, .archive, .warning, .bell, .shield]
        XCTAssertEqual(Set(HudGlyphArt.solid.keys), solid)
        XCTAssertTrue(HudGlyph.mic.hasSolid)
        XCTAssertFalse(HudGlyph.pin.hasSolid)
    }

    func testSVGPathParserHandlesTheSpriteSyntax() {
        // Packed numbers, H/V, implicit repeats and a close.
        let triangle = HudSVGPath.path("M8 .5L15.5 8L8 15.5L.5 8ZM7.25 4.25H8.75V8.75H7.25Z")
        XCTAssertEqual(triangle.boundingRect, CGRect(x: 0.5, y: 0.5, width: 15, height: 15))
        // Relative commands.
        let relative = HudSVGPath.path("m2 2h4v4h-4z")
        XCTAssertEqual(relative.boundingRect, CGRect(x: 2, y: 2, width: 4, height: 4))
        // Arcs: a full pill from two half circles.
        let pill = HudSVGPath.path("M8 6.5H16A5.5 5.5 0 0 1 21.5 12A5.5 5.5 0 0 1 16 17.5H8A5.5 5.5 0 0 1 2.5 12A5.5 5.5 0 0 1 8 6.5Z")
        let box = pill.boundingRect
        XCTAssertEqual(box.minX, 2.5, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 21.5, accuracy: 0.01)
        XCTAssertEqual(box.minY, 6.5, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 17.5, accuracy: 0.01)
        XCTAssertTrue(pill.contains(CGPoint(x: 3.2, y: 12)))
        XCTAssertFalse(pill.contains(CGPoint(x: 3.0, y: 7.5)))
    }

    func testSegmentDigitsKeepTheirCellGeometry() {
        // Digit pitch 13, colon pitch 5; width = x − 3 + 2.6.
        XCTAssertEqual(HudSegmentArt(text: "8", cells: 0).width, 12.6, accuracy: 0.001)
        XCTAssertEqual(HudSegmentArt(text: "12:48", cells: 0).width, 4 * 13 + 5 - 3 + 2.6, accuracy: 0.001)
        // Leading cells are ghosts, so the layout never shifts.
        XCTAssertEqual(HudSegmentArt(text: "8", cells: 2).width, HudSegmentArt(text: "33", cells: 2).width, accuracy: 0.001)
        // An 8 lights all seven segments; a blank cell lights none.
        XCTAssertTrue(HudSegmentArt(text: "8", cells: 0).ghost.isEmpty)
        XCTAssertTrue(HudSegmentArt(text: " ", cells: 0).lit.isEmpty)
        XCTAssertFalse(HudSegmentArt(text: "1", cells: 0).ghost.isEmpty)
        // Each segment is 2 units thick.
        let a = HudSegmentArt.segments[0].points
        XCTAssertEqual((a.map(\.y).max() ?? 0) - (a.map(\.y).min() ?? 0), 2, accuracy: 0.001)
    }

    func testLoopsFollowThePrototypeKeyframes() {
        XCTAssertEqual(HudLoop.pulse.opacity(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(HudLoop.pulse.opacity(at: 0.7), 0.3, accuracy: 0.001)
        XCTAssertEqual(HudLoop.breathe.opacity(at: 0), 0.45, accuracy: 0.001)
        XCTAssertEqual(HudLoop.breathe.opacity(at: 0.9), 1, accuracy: 0.001)
        XCTAssertEqual(HudLoop.blink.opacity(at: 0.3), 1)
        XCTAssertEqual(HudLoop.blink.opacity(at: 0.9), 0.18)
    }

    // MARK: Gallery

    func testFoundationGalleryRenders() throws {
        try export(iconsSheet, "icons")
        try export(lampsSheet, "lamps-status")
        try export(buttonsSheet, "buttons")
        try export(controlsSheet, "controls")
        try export(digitsSheet, "digits")
        try export(gaugesSheet, "gauges")
        try export(metersSheet, "meters")
        try export(scalesSheet, "scales")
        try export(todayHero, "compose-today-urgent")
        try export(recordingHero, "compose-recording")
        try export(desktopPieces, "compose-desktop")
        try exportHosted(fieldsSheet, "fields", size: CGSize(width: 760, height: 150))
    }

    // MARK: Sheets

    private var iconsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("i-* line")
            grid(HudGlyph.allCases) { HudIcon($0, size: 16).foregroundStyle(Hud.Ink.ink1) }
            caption("f-* solid (line form when a glyph has none)")
            grid(HudGlyph.allCases.filter(\.hasSolid)) { HudIcon($0, size: 16, solid: true).foregroundStyle(Hud.Ink.ink1) }
            caption("32 pt")
            HStack(spacing: 14) {
                ForEach([HudGlyph.calendar, .mic, .micOff, .speaker, .video, .keyboard, .gauge, .people, .history, .trash], id: \.self) {
                    HudIcon($0, size: 32).foregroundStyle(Hud.Ink.ink1)
                }
            }
            HStack(spacing: 14) {
                ForEach([HudGlyph.calendar, .mic, .micOff, .speaker, .video, .keyboard, .gauge, .tape, .transcript, .bell], id: \.self) {
                    HudIcon($0, size: 32, solid: true).foregroundStyle(Hud.Ink.ink1)
                }
            }
            caption("telltales: off · lit · paren · mod")
            HStack(spacing: 16) {
                HudTelltale(.calendar, .off); HudTelltale(.mic, .off); HudTelltale(.speaker, .off)
                HudTelltale(.calendar, .teal); HudTelltale(.queue, .teal); HudTelltale(.mic, .teal)
                HudTelltale(.speaker, .teal); HudTelltale(.accessibility, .teal); HudTelltale(.keyboard, .teal)
                HudTelltale(.mic, .white); HudTelltale(.video, .amber)
                HudTelltale(.mic, .amber, paren: true); HudTelltale(.mic, .red, paren: true)
                HudTelltale(.speaker, .red, badge: .bang); HudTelltale(.calendar, .red, badge: .bang); HudTelltale(.speaker, .amber, badge: .x)
                HudTelltaleTile(.warning, .red); HudTelltaleTile(.transcript, .amber)
            }
            caption("mark · tile · brand · logo · task marks · priority")
            HStack(spacing: 18) {
                HudMark(width: 46, glow: 6); HudMark(); HudAppTile(); HudBrand()
                HudLogo().foregroundStyle(Hud.Ink.ink1)
                ForEach(TaskStatus.allCases) { HudStateMark(state: $0) }
                ForEach(TaskStatus.allCases) { HudStateMark(state: $0, size: 32) }
                HudPriorityBars(level: 1); HudPriorityBars(level: 2, tint: Hud.Ink.ink1); HudPriorityBars(level: 3, tint: Hud.Ink.signal)
            }
        }
        .padding(24)
        .frame(width: 900, alignment: .leading)
        .background(Color.black)
    }

    private var lampsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            caption("lamps 8×4 · dot · off · dim")
            HStack(spacing: 22) {
                HudLamp(.amber); HudLamp(.red); HudLamp(.teal); HudLamp(.white); HudLamp(.dim); HudLamp(.off)
                HudLamp(.amber, form: .dot); HudLamp(.red, form: .dot); HudLamp(.teal, form: .dot); HudLamp(.white, form: .dot); HudLamp(.off, form: .dot)
            }
            HStack(spacing: 22) {
                ForEach([Hud.LampColor.amber, .red, .teal, .white, .off], id: \.self) { HudLamp($0).scaleEffect(4).frame(width: 40, height: 24) }
            }
            caption("cells · busy")
            HStack(spacing: 22) {
                HudCells(done: 1, total: 5)
                HudCells(states: [.done, .current, .off, .off])
                HudCells(states: [.done, .done, .done, .current])
                HudBusy()
            }
            caption("status shapes 12 · 14 · 24 · well")
            HStack(spacing: 16) {
                ForEach(HudStatus.allCases, id: \.self) { HudStatusShape($0) }
                ForEach(HudStatus.allCases, id: \.self) { HudStatusShape($0, size: HudStatusShape.ear) }
                ForEach(HudStatus.allCases, id: \.self) { HudStatusShape($0, size: HudStatusShape.hero) }
                HudStatusShape(.off, size: HudStatusShape.hero, tint: Hud.Ink.live)
            }
            HStack(spacing: 16) {
                HudStatusWell(.err); HudStatusWell(.off, tint: Hud.Ink.live); HudStatusWell(.stop); HudStatusWell(.warn)
            }
            caption("status words")
            HStack(spacing: 24) {
                HudStatusWord(.ok, "Connected"); HudStatusWord(.dim, "Not set"); HudStatusWord(.warn, "Needs you")
                HudStatusWord(.err, "Failed"); HudStatusWord(.off(), "Access off"); HudStatusWord(.off(blocking: true), "Mic off")
            }
        }
        .padding(24)
        .frame(width: 760, alignment: .leading)
        .background(Color.black)
    }

    private var buttonsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("primary · secondary · danger · ghost — lg / regular / sm / xs")
            ForEach([HudButtonStyle.Size.large, .regular, .small, .mini], id: \.self) { size in
                HStack(spacing: 8) {
                    HudButton("Join", key: "⌘J", kind: .primary, size: size) {}
                    HudButton("Record", lamp: .red, key: "⌘R", size: size) {}
                    HudButton("Later", key: "esc", size: size) {}
                    HudButton("Finished", glyph: .history, size: size) {}
                    HudButton("Clear", glyph: .trash, kind: .danger, size: size) {}
                    HudButton("Rename", kind: .ghost, size: size) {}
                    HudButton("Export", glyph: .share, trailingGlyph: .chevronDown, size: size) {}
                    HudButton("Open notes", key: "↩", kind: .primary, size: size) {}
                }
            }
            caption("pressed · disabled")
            HStack(spacing: 12) {
                label("Join", key: "↩").frame(height: 28).padding(.horizontal, 12)
                    .background(HudKeyFace(kind: .primary, radius: 8, isPressed: true)).foregroundStyle(Hud.Ink.onKey)
                    .environment(\.hudButtonKind, .primary)
                label("Later", key: "esc").frame(height: 28).padding(.horizontal, 12)
                    .background(HudKeyFace(kind: .secondary, radius: 8, isPressed: true)).foregroundStyle(Hud.Ink.ink1)
                    .environment(\.hudButtonKind, .secondary)
                label("Hover", key: "⌘R").frame(height: 28).padding(.horizontal, 12)
                    .background(HudKeyFace(kind: .secondary, radius: 8, isHovering: true)).foregroundStyle(Hud.Ink.ink1)
                    .environment(\.hudButtonKind, .secondary)
                HudButton("Stop", key: "esc") {}.disabled(true)
                HudButton("Join", key: "↩", kind: .primary) {}.disabled(true)
            }
            caption("icon · icon on · framed · framed sm · knobs · keycaps")
            HStack(spacing: 12) {
                HudIconButton(.tape) {}; HudIconButton(.tape, isOn: true) {}; HudIconButton(.window) {}; HudIconButton(.pin) {}
                HudIconButton(.more, framed: true) {}; HudIconButton(.copy, framed: true) {}
                HudIconButton(.edit, framed: true, small: true) {}; HudIconButton(.trash, framed: true, small: true, tint: Hud.Ink.danger) {}
                HudKnob(.mic, lamp: .white) {}; HudKnob(.micOff, tint: Hud.Ink.ink3, lamp: .off) {}
                HudKnob(.micOff, tint: Hud.Ink.signal, lamp: .amber) {}; HudKnob(.stop, tint: Hud.Ink.live) {}
                HudKnob(.play, small: true) {}
                HudKeycap("esc"); HudKeycap("↩"); HudKeycap("⇧⌘C"); HudKeycap("tab")
            }
            .padding(.bottom, 10)
            caption("actions row · console")
            HudActions {
                HudLamp(.teal); Text(verbatim: "Synced with Reminders")
            } buttons: {
                HudButton("Clear", glyph: .trash, kind: .danger, size: .small) {}
                HudButton("Finished", glyph: .history, size: .small) {}
                HudButton("Open notes", key: "↩", kind: .primary, size: .small) {}
            }
            HudConsole {
                HudLamp(.teal); Text(verbatim: "Crenel will ask to record when it starts")
            } buttons: {
                HudButton("Record", lamp: .red, key: "⌘R", size: .small) {}
                HudButton("Join", key: "⌘J", kind: .primary, size: .small) {}
            }
        }
        .padding(24)
        .frame(width: 900, alignment: .leading)
        .background(Color.black)
    }

    private var controlsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("tabs with lamp · annunciator · segmented · pills")
            HStack(spacing: 28) {
                HudBrand()
                HudTabs(items: [.init(tab: 0, title: "Today"), .init(tab: 1, title: "Tasks", badge: 5)], selection: .constant(0))
                HudTabs(items: [.init(tab: 0, title: "Today"), .init(tab: 1, title: "Tasks", badge: 5)], selection: .constant(1))
                HudAnnunciator(items: [.init(0, "All"), .init(1, "Needs you", count: 2), .init(2, "For you")], selection: .constant(0))
                HudAnnunciator(items: [.init(0, "All"), .init(1, "Needs you", count: 2), .init(2, "For you")], selection: .constant(1))
            }
            HStack(spacing: 20) {
                HudSegmented(items: [(0, "All"), (1, "Needs you"), (2, "For you")], selection: .constant(0))
                HudSegmented(items: [(0, "None"), (1, "Low"), (2, "Medium"), (3, "High")], selection: .constant(2)) { level in
                    if level > 0 { HudPriorityBars(level: level, tint: level == 3 ? Hud.Ink.signal : (level == 2 ? Hud.Ink.ink1 : Hud.Ink.ink2)) }
                }
                Button("Today") {}.buttonStyle(HudPillStyle(isOn: true))
                Button("Tomorrow") {}.buttonStyle(HudPillStyle())
            }
            caption("toggle · select · fields · chips")
            HStack(spacing: 20) {
                HudSwitch(isOn: false); HudSwitch(isOn: true)
                HudSelect(selection: .constant(0), options: [(0, "Forever"), (1, "7 days")])
            }
            HStack(spacing: 8) {
                HudChip("Today 15:00", lamp: .amber); HudChip("Every week", lamp: .white)
                HudChip("High") { HudPriorityBars(level: 3, tint: Hud.Ink.signal) }
                HudChip("Tomorrow", glyph: .plus, style: .outline)
                HudChip("48 min", glyph: .clock, style: .tag); HudChip("Google Meet", glyph: .video, style: .tag)
                HudFaces(initials: ["D", "E", "M", "+1"])
                HudCaret(); HudSpinner(); HudBigKeycap("fn", glyph: .globe, lamp: .teal); HudIconTile(.spark)
            }
            caption("group header · rows · hover slab")
            VStack(spacing: 0) {
                HudGroupHeader(title: "Today", count: 3)
                HudRow(.twoLine) {
                    HudTimeColumn("16:00")
                    HudIcon(.place).foregroundStyle(Hud.Ink.ink3).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Lunch with Deniz").hud(.body)
                        Text(verbatim: "Karaköy Lokantası").hud(.meta)
                    }
                }
                HudRow(.twoLine) {
                    HudTimeColumn("17:30")
                    HudIcon(.video).foregroundStyle(Hud.Ink.ink3).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Partner call").hud(.body)
                        Text(verbatim: "Zoom · from Mira Lund").hud(.meta)
                    }
                    Spacer()
                    HStack(spacing: 8) { HudStatusShape(.warn); Text(verbatim: "Invite").hud(.meta, Hud.Ink.ink2) }.padding(.top, 2)
                }
                .background(RoundedRectangle(cornerRadius: Hud.Row.radius).fill(Hud.Ink.hover))
                HudGroupHeader(title: "Today") { HudCells(done: 1, total: 5) }
                HudRow(.task) {
                    HudStateMark(state: .inProgress)
                    Text(verbatim: "Write release notes").hud(.body)
                    Spacer()
                    HudReadout("25", unit: "min", height: 10, color: Hud.Ink.signal)
                }
                HudRow(.task) {
                    HudStateMark(state: .open)
                    Text(verbatim: "Reply to Deniz about pricing").hud(.body)
                    Spacer()
                    HudPriorityBars(level: 3, tint: Hud.Ink.signal)
                    Text(verbatim: "Yesterday").hud(.meta, Hud.Ink.live)
                }
            }
            .frame(width: 532)
            caption("well · frame · panel · sheet · group card · rail")
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) { HudSegmentDigits("48:12", height: 20); Text(verbatim: "recorded").hud(.meta) }
                        .padding(.horizontal, 16).frame(width: 120, alignment: .leading)
                    HudWellDivider()
                    VStack(alignment: .leading, spacing: 8) { HudSegmentDigits("3", height: 20, color: Hud.Ink.signal); Text(verbatim: "for you to do").hud(.meta) }
                        .padding(.horizontal, 16).frame(width: 120, alignment: .leading)
                }
                .padding(.vertical, 14)
                .hudWell()
                HudFrame("Details") {
                    Text(verbatim: "Recorded on this Mac").hud(.meta)
                }
                .frame(width: 170)
                Text(verbatim: "Panel").hud(.label, Hud.Ink.ink2).padding(16).frame(width: 90, height: 60, alignment: .topLeading).hudPanel()
                Text(verbatim: "Sheet").hud(.label, Hud.Ink.ink2).padding(16).frame(width: 90, height: 60, alignment: .topLeading).hudSheet()
                HudRail(items: [.init(value: 0, glyph: .gauge, title: "Today", readout: "in 33 min"),
                                .init(value: 1, glyph: .tape, title: "Meetings", readout: "12"),
                                .init(value: 2, glyph: .queue, title: "Tasks", readout: "4")], selection: .constant(0))
                    .frame(width: 200)
            }
            .padding(12)
            .background(Hud.Layer.window)
        }
        .padding(24)
        .frame(width: 980, alignment: .leading)
        .background(Color.black)
    }

    private var digitsSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            caption("13 ear · 24 hero · 34 recording")
            HStack(alignment: .bottom, spacing: 28) {
                HudSegmentDigits("14:30", height: 13)
                HudReadout("33", unit: "min", cells: 2)
                HudReadout("8", unit: "min", cells: 2, color: Hud.Ink.signal)
                HudReadout("12", unit: "s", cells: 2, color: Hud.Ink.live)
                HudSegmentDigits("33", height: 24, cells: 2)
                HudSegmentDigits("8", height: 24, cells: 2, color: Hud.Ink.signal)
                HudSegmentDigits("12:48", height: 34)
            }
            HStack(alignment: .bottom, spacing: 28) {
                HudSegmentDigits("0123456789", height: 24)
                HudSegmentDigits("--:--", height: 15)
                HudSegmentDigits("1:02:07", height: 20, color: Hud.Ink.ok)
                HudSegmentDigits("42", height: 13, cells: 3)
                HudSegmentDigits("4.2", height: 20)
            }
            HudSegmentDigits("12:48", height: 72)
        }
        .padding(28)
        .frame(width: 820, alignment: .leading)
        .background(Color.black)
    }

    private var gaugesSheet: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(spacing: 44) {
                HudGauge(value: 0) {
                    HudSegmentDigits("14:30", height: 17)
                    Text(verbatim: "in 3 h 48").hud(.micro, Hud.Ink.ink3)
                }
                HudGauge(value: 0.55, zones: HudGaugeZone.countdown) {
                    HudSegmentDigits("33", height: 24, cells: 2)
                    Text(verbatim: "min").hud(.micro, Hud.Ink.ink3)
                }
                HudGauge(value: 0.133, tint: Hud.Ink.signal, zones: HudGaugeZone.redline) {
                    HudSegmentDigits("8", height: 24, cells: 2, color: Hud.Ink.signal)
                    Text(verbatim: "min").hud(.micro, Hud.Ink.signal.opacity(0.7))
                }
                HudGauge(value: 0.3, tint: Hud.Ink.signal) {
                    HudSegmentDigits("18", height: 24, cells: 2, color: Hud.Ink.signal)
                    Text(verbatim: "min left").hud(.micro, Hud.Ink.signal.opacity(0.7))
                }
                HudRestingGauge()
                HudRestingGauge(status: .err)
                HudRestingGauge(status: .off)
            }
            HStack(spacing: 60) {
                HudGauge(value: 0.55, size: 148, zones: HudGaugeZone.countdown, labels: ["0", "15", "30", "45", "60"]) {
                    HudSegmentDigits("33", height: 30, cells: 2)
                    Text(verbatim: "min").hud(.micro, Hud.Ink.ink3)
                }
                HudGauge(value: 0.4, ticks: 5, major: 0, size: 148, tint: Hud.Ink.ok) {
                    HudSegmentDigits("2", height: 30)
                    Text(verbatim: "of 5 done").hud(.micro, Hud.Ink.ink3)
                }
                HudGauge(value: 1, ticks: 90, size: 220) {
                    HudMark(width: 46, glow: 6).padding(.bottom, 7)
                    HudSegmentDigits("10:42", height: 16)
                }
            }
        }
        .padding(50)
        .background(Color.black)
    }

    private var metersSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("VU: level + peak hold · red zone · off")
            VStack(spacing: 14) {
                HudVUMeter(level: 0.43, peak: 0.8)
                HudVUMeter(level: 0.4, peak: 0.4)
                HudVUMeter(level: 0.97, peak: 0.97)
                HudVUMeter(level: 0, isOff: true)
            }
            .frame(width: 376)
            caption("capacity scale")
            HudCapacityScale(level: 0.6, peak: 0.75).frame(width: 232)
            caption("ladder · quiet · tinted")
            HStack(spacing: 24) {
                HudLadder(level: 1); HudLadder(level: 0.6); HudLadder(level: 0, quiet: true); HudLadder(level: 0.9, tint: Hud.Ink.signal)
                HudLadder(level: 1).scaleEffect(3).frame(width: 90, height: 44)
            }
            caption("chart recorder")
            HudChartRecorder(samples: Self.chartSamples).frame(width: 512)
            caption("scanner (static frame) · fuse")
            HStack(spacing: 12) {
                Text(verbatim: "Listening for 3 speakers").hud(.meta, Hud.Ink.ink2)
                Spacer()
                Text(verbatim: "about 1 min").hud(.meta)
            }
            .padding(.horizontal, 12).frame(width: 512, height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 1, opacity: 0.04)))
            .hudScanner(radius: 10, fixedPhase: 0.4)
            VStack(spacing: 14) {
                HudFuse(fraction: 0.55); HudFuse(fraction: 0.8, color: Hud.Ink.signal); HudFuse(fraction: 0.4, color: Hud.Ink.live)
            }
            .frame(width: 300)
            caption("LED stack · small · dot matrix · capsules · stations")
            HStack(alignment: .bottom, spacing: 22) {
                HudLEDStack(lit: 5, tone: .past); HudLEDStack(lit: 8); HudLEDStack(lit: 0)
                HudLEDStack(lit: 4, cells: 6, tone: .past, small: true); HudLEDStack(lit: 6, cells: 6, small: true); HudLEDStack(lit: 0, cells: 6, small: true)
                HudDotMatrix(value: 0.64, count: 78, mark: 0.46).padding(.bottom, 8)
                HudCapsules(done: 1, underWay: 1, total: 5)
            }
            HudStations(titles: ["Saved", "Uploading", "Transcript", "Notes"], current: 1).frame(width: 512)
            HudStations(titles: ["Saved", "Uploaded", "Transcribed", "Writing notes"], current: 3).frame(width: 512)
        }
        .padding(24)
        .frame(width: 600, alignment: .leading)
        .background(Color.black)
    }

    private var scalesSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("day ruler")
            HudDayRuler(now: 10.7, events: [.init(14.5, 15.25, .focus), .init(16, 17), .init(17.5, 18, .invite), .init(19, 20, .dim)])
                .frame(width: 512)
            HudDayRuler(now: 10.7, events: [.init(10.83, 11.5, .amber), .init(9, 10, .dim), .init(16, 17), .init(17.5, 18, .invite), .init(19, 20, .dim)])
                .frame(width: 512)
            caption("day ruler, wide")
            HudDayRuler(now: 10.7, events: [
                .init(9, 9.5, .dim, title: "Standup"), .init(11.25, 12, .focus, title: "Design review"),
                .init(13, 14, .normal, title: "Lunch with Deniz"), .init(16.5, 17.5, .invite, title: "Partner call"),
                .init(19, 20, .normal, title: "Gym")
            ], wide: true)
                .frame(width: 930)
            caption("day ruler, wide: back-to-back events · the second hovered")
            ForEach([Int?.none, 1], id: \.self) { hover in
                HudDayRuler(now: 15.6, events: [
                    .init(18, 18.5, .focus, title: "Edda Dev. Sync"), .init(18.5, 19, .normal, title: "BB Dev. Sync")
                ], wide: true, previewHover: hover)
                    .frame(width: 930)
            }
            caption("ramp: in plan · past the plan")
            HStack(alignment: .bottom, spacing: 10) {
                HudRamp(elapsed: 768, plan: 3600); Text(verbatim: "of 60 min").hud(.micro)
                HudRamp(elapsed: 4000, plan: 3600).padding(.leading, 30); Text(verbatim: "of 60 min").hud(.micro)
            }
            caption("waveform + tuner · talk bar")
            VStack(spacing: 4) {
                HudWaveform(samples: HudWaveform.demoSamples(), progress: 0.25)
                HudTunerScale(minutes: 48)
            }
            .frame(width: 476)
            HStack(spacing: 12) {
                HudTalkBar(shares: [0.46, 0.38, 0.16])
                HStack(spacing: 6) { HudSpeakerDot(index: 0); Text(verbatim: "You").hud(.meta) }
                HStack(spacing: 6) { HudSpeakerDot(index: 1); Text(verbatim: "Deniz").hud(.meta) }
                HStack(spacing: 6) { HudSpeakerDot(index: 2); Text(verbatim: "Ece").hud(.meta) }
            }
            .frame(width: 512)
            caption("track · lane")
            VStack(spacing: 10) {
                HudTrack(value: 0.46); HudTrack(value: 0.38, tint: Hud.Ink.ink2, glows: false); HudTrack(value: 0.16, tint: Hud.Ink.ink4, glows: false)
                HudLane(segments: [(0.09, 0), (0.14, 1), (0.06, 0), (0.08, 2), (0.11, 1), (0.17, 0), (0.05, 2), (0.13, 1), (0.14, 0)])
            }
            .frame(width: 232)
            caption("schematic: at rest · two on · all on")
            HStack(spacing: 40) {
                HudSchematic(); HudSchematic(lit: [.notifications, .speakers]); HudSchematic(lit: Set(HudSchematic.Part.allCases))
            }
        }
        .padding(24)
        .frame(width: 990, alignment: .leading)
        .background(Color.black)
    }

    /// AppKit-backed controls (text fields, menus) only draw in a hosted window.
    private var fieldsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                HudSwitch(isOn: false); HudSwitch(isOn: true)
                HudSelect(selection: .constant(0), options: [(0, "Forever"), (1, "7 days")])
                HudTextField(text: .constant("sk-ant-api03"), prompt: "API key").frame(width: 160)
                HudTextField(text: .constant(""), prompt: "Name").frame(width: 120)
                HudSearchField(text: .constant("")).frame(width: 180)
            }
            HStack(spacing: 12) {
                HudIcon(.plus).foregroundStyle(Hud.Ink.ink3)
                Text(verbatim: "Add a task — “call mom tomorrow 3pm”").hud(.body, Hud.Ink.ink3)
                Spacer()
                Text(verbatim: "↩").hud(.micro)
            }
            .hudField(height: 44, radius: 12, padding: 10)
            .frame(width: 532)
        }
        .padding(24)
        .frame(width: 760, height: 150, alignment: .topLeading)
        .background(Color.black)
    }

    // MARK: Compositions (to compare 1:1 with prototype screenshots)

    /// `o-today-urgent`: hero + console + ruler, 560 pt panel.
    private var todayHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    HudBrand()
                    HudTabs(items: [.init(tab: 0, title: "Today"), .init(tab: 1, title: "Tasks", badge: 5)], selection: .constant(0))
                }
                Spacer()
                HStack(spacing: 2) { HudIconButton(.tape) {}; HudIconButton(.window) {}; HudIconButton(.pin) {} }
            }
            .frame(height: 32)
            .padding(.bottom, 8)
            HStack(spacing: 16) {
                HudGauge(value: 0.133, tint: Hud.Ink.signal, zones: HudGaugeZone.redline) {
                    HudSegmentDigits("8", height: 24, cells: 2, color: Hud.Ink.signal)
                    Text(verbatim: "min").hud(.micro, Hud.Ink.signal.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Design review").hud(.hero)
                    HStack(spacing: 6) { Text(verbatim: "10:50").hud(.meta); Text(verbatim: "·").hud(.meta, Hud.Ink.ink4); Text(verbatim: "Google Meet").hud(.meta) }
                    HStack(spacing: 6) { HudIcon(.people, size: 12).foregroundStyle(Hud.Ink.ink4); Text(verbatim: "Deniz, Ece and 2 others").hud(.meta) }
                }
                Spacer()
            }
            .padding(.leading, 6).padding(.top, 4).padding(.bottom, 12)
            HudConsole {
                HudLamp(.teal); Text(verbatim: "Crenel will ask to record when it starts")
            } buttons: {
                HudButton("Record", lamp: .red, key: "⌘R", size: .small) {}
                HudButton("Join", key: "⌘J", kind: .primary, size: .small) {}
            }
            .padding(.horizontal, 2).padding(.bottom, 12)
            HudDayRuler(now: 10.7, events: [.init(10.83, 11.5, .amber), .init(16, 17), .init(17.5, 18, .invite), .init(19, 20, .dim)])
                .padding(.horizontal, 10)
            HudGroupHeader(title: "Today", count: 3).padding(.top, 4)
            HudRow(.twoLine) {
                HudTimeColumn("16:00")
                HudIcon(.place).foregroundStyle(Hud.Ink.ink3).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Lunch with Deniz").hud(.body)
                    Text(verbatim: "Karaköy Lokantası").hud(.meta)
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: 560)
        .background(Color.black)
    }

    /// `o-recording`: clock, ramp, knobs, chart, VU rows.
    private var recordingHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        HudLamp(.red, form: .dot)
                        Text(verbatim: "Recording").hud(.label)
                        Text(verbatim: "Design review").hud(.meta)
                    }
                    HudSegmentDigits("12:49", height: 34)
                    HStack(alignment: .bottom, spacing: 10) { HudRamp(elapsed: 769, plan: 3600); Text(verbatim: "of 60 min").hud(.micro) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudBleed(Hud.Ink.live)
                HudKnob(.mic, lamp: .white) {}
                HudKnob(.stop, tint: Hud.Ink.live) {}
            }
            .padding(.horizontal, 10).padding(.top, 4)
            VStack(spacing: 6) {
                HudChartRecorder(samples: Self.chartSamples)
                HStack { Text(verbatim: "−2:00").hud(.micro); Spacer(); Text(verbatim: "−1:00").hud(.micro); Spacer(); Text(verbatim: "now").hud(.micro) }
            }
            .padding(.horizontal, 10).padding(.top, 20)
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    HudTelltale(.mic, .white); Text(verbatim: "Your mic").hud(.label, Hud.Ink.ink2).frame(width: 96, alignment: .leading)
                    HudVUMeter(level: 0.43, peak: 0.8)
                }
                .padding(.horizontal, 10).frame(height: 32)
                HStack(spacing: 12) {
                    HudTelltale(.speaker, .red, badge: .bang); Text(verbatim: "The call").hud(.label, Hud.Ink.ink2).frame(width: 96, alignment: .leading)
                    HudVUMeter(level: 0.4, peak: 0.4)
                }
                .padding(.horizontal, 10).frame(height: 32)
                HStack(spacing: 12) {
                    HudTelltale(.mic, .amber, paren: true).padding(.horizontal, -4)
                    Text(verbatim: "Your mic").hud(.label, Hud.Ink.ink3).frame(width: 96, alignment: .leading)
                    HudVUMeter(level: 0, isOff: true)
                }
                .padding(.horizontal, 10).frame(height: 32)
            }
            .padding(.top, 16)
            HStack(spacing: 12) { HudTelltale(.accessibility, .teal); Text(verbatim: "Your mic follows mute in Zoom").hud(.meta) }
                .padding(.horizontal, 10).frame(height: 32).padding(.top, 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 16)
        .frame(width: 560)
        .background(Color.black)
    }

    /// Pieces of `d-today`: the sidebar brand and systems row, a hero panel, a tile.
    private var desktopPieces: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HudAppTile(); Text(verbatim: "Crenel").font(Hud.font(13.5, .semibold)).foregroundStyle(Hud.Ink.ink1)
                    Spacer(); HudSegmentDigits("10:42", height: 10, color: Hud.Ink.ink3, glows: false)
                }
                .padding(.horizontal, 8)
                HudRail(items: [.init(value: 0, glyph: .gauge, title: "Today", readout: "in 33 min"),
                                .init(value: 1, glyph: .tape, title: "Meetings", readout: "12"),
                                .init(value: 2, glyph: .queue, title: "Tasks", readout: "4"),
                                .init(value: 3, glyph: .waveform, title: "Dictation", readout: "fn")], selection: .constant(0))
                HStack {
                    HudTelltale(.calendar, .teal); Spacer(); HudTelltale(.queue, .teal); Spacer(); HudTelltale(.mic, .teal); Spacer()
                    HudTelltale(.speaker, .red, paren: true); Spacer(); HudTelltale(.accessibility, .amber, paren: true); Spacer()
                    HudTelltale(.keyboard, .teal)
                }
                .padding(12)
            }
            .padding(12)
            .frame(width: 224)
            .background(Hud.Layer.sidebar)
            .hudSurface(Hud.Layer.sidebar)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 28) {
                    HudGauge(value: 0.55, size: 148, zones: HudGaugeZone.countdown, labels: ["0", "15", "30", "45", "60"]) {
                        HudSegmentDigits("33", height: 30, cells: 2)
                        Text(verbatim: "min").hud(.micro, Hud.Ink.ink3)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "Next meeting").hud(.meta)
                        Text(verbatim: "Design review").hud(.page)
                        HStack(spacing: 10) { HudFaces(initials: ["D", "E", "M", "+1"]); Text(verbatim: "Deniz, Ece and 2 others").hud(.meta) }
                    }
                    Spacer()
                    HStack(spacing: 8) { HudButton("Copy link", glyph: .copy) {}; HudButton("Calendar", glyph: .calendar) {} }
                }
                .padding(20)
                .hudPanel()
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) { HudIcon(.queue).foregroundStyle(Hud.Ink.ink3); Text(verbatim: "Tasks").hud(.label, Hud.Ink.ink2); Spacer(); HudCapsules(done: 1, underWay: 1, total: 5) }
                        HudReadout("4", unit: "open today", height: 28)
                    }
                    .padding(16).frame(width: 280, alignment: .leading).hudPanel()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) { HudIcon(.tape).foregroundStyle(Hud.Ink.ink3); Text(verbatim: "On tape").hud(.label, Hud.Ink.ink2) }
                        HudReadout("4:12", unit: "h", height: 28)
                        HStack(alignment: .bottom, spacing: 26) {
                            HudLEDStack(lit: 5, tone: .past); HudLEDStack(lit: 8); HudLEDStack(lit: 0); HudLEDStack(lit: 0); HudLEDStack(lit: 0)
                        }
                    }
                    .padding(16).frame(width: 280, alignment: .leading).hudPanel()
                }
            }
            .padding(24)
            .background(Hud.Layer.window)
            .hudSurface(Hud.Layer.window)
        }
        .background(Hud.Layer.window)
    }

    // MARK: Helpers

    private static let chartSamples: [Double] = {
        var seed = 11.0
        return (0..<128).map { _ in
            seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233_280)
            let random = seed / 233_280
            return random < 0.12 ? 0.08 : 0.12 + pow(random, 1.4) * 0.85
        }
    }()

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).hud(.micro, Hud.Ink.ink3)
    }

    private func label(_ title: String, key: String) -> some View {
        HudButtonLabel(title, key: key).font(Hud.Style.label.font)
    }

    private func grid<Content: View>(_ glyphs: [HudGlyph], @ViewBuilder cell: @escaping (HudGlyph) -> Content) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: 14), alignment: .leading, spacing: 10) {
            ForEach(glyphs, id: \.self) { glyph in
                VStack(spacing: 5) {
                    cell(glyph)
                    Text(verbatim: glyph.rawValue).font(Hud.font(7.5)).foregroundStyle(Hud.Ink.ink4).lineLimit(1)
                }
            }
        }
    }

    private func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    private func alpha(_ color: Color) -> Double {
        Double(NSColor(color).usingColorSpace(.sRGB)!.alphaComponent)
    }

    private func exportHosted(_ view: some View, _ name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/foundation/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }

    /// Renders through SwiftUI's own renderer (Canvas filters and shape-style shadows
    /// need it) at 2×, checks it produced pixels, and writes the PNG when exporting.
    private func export(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "\(name) did not render")
        XCTAssertGreaterThan(image.size.width, 10)
        XCTAssertGreaterThan(image.size.height, 10)
        guard FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit") else { return }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/foundation/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: path)
    }
}
