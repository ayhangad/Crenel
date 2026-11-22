import SwiftUI

/// Recording: the elapsed time as the one big number, two push knobs (mic, stop), the
/// last two minutes on a chart recorder, a peak-hold meter per source, and whatever
/// needs saying in one line each.
struct RecordingSurface: View {
    /// One line under the meters: a status shape and a sentence.
    struct Warning: Identifiable, Equatable {
        let status: HudStatus
        let text: String
        var id: String { text }
    }

    let startedAt: Date
    /// The calendar event being recorded, when it is known.
    var title: String?
    /// The event's planned length; the ramp is only drawn when this is known.
    var plannedLength: TimeInterval?
    /// The meeting mic gate; nil when the mic is simply recorded.
    var microphone: MeetingMicrophoneState?
    var microphoneLevel: Double = 0
    var callLevel: Double = 0
    /// The call's audio stream dropped.
    var callFailed = false
    /// Chart recorder samples, one a second, oldest first.
    var levels: [Double] = []
    /// The app whose mute button the mic follows ("Zoom"), when that is verified.
    var muteFollows: String?
    var warnings: [Warning] = []
    /// A fixed clock, for renders and tests.
    var now: Date?
    /// Meters start full and fall: only when the panel opens from closed.
    var ignite = false
    var onToggleMicrophone: () -> Void = {}
    var onStop: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Three groups, 28 apart: control (state, clock, plan, knobs), signal (the
            // chart and its scale), inputs (mic, call, mute or warnings at 20 apart).
            header
                .padding(.horizontal, Hud.Layout.rowPad)
                .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)

            VStack(spacing: Hud.Layout.pair) {
                HudChartRecorder(samples: levels)
                HStack {
                    Text(verbatim: "−2:00")
                    Spacer()
                    Text(verbatim: "−1:00")
                    Spacer()
                    Text("now")
                }
                .hud(.micro)
                .hudTrim(.micro)
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .padding(.top, Hud.Layout.section)
            .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Hud.Layout.item) {
                microphoneRow
                callRow
                if warnings.isEmpty, let muteFollows, microphone != nil, microphone != .unknown {
                    HStack(spacing: 12) {
                        HudTelltale(.accessibility, .teal).padding(-Hud.Layout.glyphInset)
                        Text("Your mic follows mute in \(muteFollows)").hudTrimmed(.meta)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(warnings) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        HudStatusShape(warning.status)
                            .frame(width: 13)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(verbatim: warning.text)
                            .hud(.meta, Hud.Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .padding(.top, Hud.Layout.section)
            .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: Hud.Layout.block) {
                HStack(spacing: 8) {
                    HudLamp(.red, form: .dot, loop: .pulse)
                    Text("Recording").hudTrimmed(.label, Hud.Ink.ink1)
                    if let title, !title.isEmpty {
                        Text(verbatim: title).hudTrimmed(.meta, Hud.Ink.ink2).truncationMode(.tail)
                    }
                }
                clock { elapsed in
                    let text = HudFormat.elapsed(elapsed)
                    HudSegmentDigits(text.count == 4 ? "0\(text)" : text, height: 34)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(NotchAccessibilityContract.recordingDurationLabel(text))
                    if let plannedLength, plannedLength >= 60 {
                        let minutes = Int((plannedLength / 60).rounded())
                        HStack(alignment: .bottom, spacing: 10) {
                            HudRamp(elapsed: elapsed, plan: plannedLength)
                            Text("of \(minutes) min").hudTrimmed(.micro, Hud.Ink.ink3)
                        }
                        .help("Planned length: \(minutes) min")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Planned length: \(minutes) minutes")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudBleed(Hud.Ink.live)

            if let microphone {
                microphoneKnob(microphone)
            }
            HudKnob(.stop, tint: Hud.Ink.live, help: "Stop and write notes (right-click to delete)", action: onStop)
                .contextMenu {
                    Button("Delete recording", role: .destructive, action: onDelete)
                }
                .accessibilityLabel("Stop recording")
        }
    }

    /// The elapsed time, ticking once a second unless the clock is fixed.
    @ViewBuilder
    private func clock<Content: View>(@ViewBuilder _ content: @escaping (TimeInterval) -> Content) -> some View {
        if let now {
            VStack(alignment: .leading, spacing: Hud.Layout.block) { content(max(0, now.timeIntervalSince(startedAt))) }
        } else {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                VStack(alignment: .leading, spacing: Hud.Layout.block) { content(max(0, context.date.timeIntervalSince(startedAt))) }
            }
        }
    }

    @ViewBuilder
    private func microphoneKnob(_ state: MeetingMicrophoneState) -> some View {
        Group {
            switch state {
            case .open:
                HudKnob(.mic, lamp: .white, help: "Meeting mic on. Click to turn it off for privacy (⌥⌘M)", action: onToggleMicrophone)
            case .closed:
                HudKnob(.micOff, tint: Hud.Ink.ink3, lamp: .off, help: "Meeting mic off (⌥⌘M)", action: onToggleMicrophone)
            case .unknown:
                HudKnob(.micOff, tint: Hud.Ink.signal, lamp: .amber, lampLoop: .blink, help: "Mic state unknown, kept off",
                        action: onToggleMicrophone)
            }
        }
        .accessibilityLabel(NotchAccessibilityContract.microphoneGateLabel(state))
    }

    // MARK: Sources

    private var microphoneRow: some View {
        let isOn = microphone == nil || microphone == .open
        return HStack(spacing: 12) {
            Group {
                switch microphone {
                case .closed:
                    HudTelltale(.micOff, .off)
                case .unknown:
                    HudTelltale(.mic, .amber, paren: true).padding(.horizontal, -4)
                default:
                    HudTelltale(.mic, .white)
                }
            }
            .padding(.horizontal, -Hud.Layout.glyphInset)
            Text("Your mic").hudTrimmed(.body, isOn ? Hud.Ink.ink2 : Hud.Ink.ink3)
                .frame(width: 96, alignment: .leading)
            HudVUMeter(level: isOn ? microphoneLevel : 0, isOff: !isOn, ignite: ignite && isOn)
        }
        .padding(.vertical, -Hud.Layout.glyphInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOn ? "Your mic is on" : "Your mic is off")
    }

    private var callRow: some View {
        HStack(spacing: 12) {
            Group {
                if callFailed {
                    HudTelltale(.speaker, .red, badge: .bang)
                } else {
                    HudTelltale(.speaker, .white)
                }
            }
            .padding(.horizontal, -Hud.Layout.glyphInset)
            Text("The call").hudTrimmed(.body, Hud.Ink.ink2)
                .frame(width: 96, alignment: .leading)
            HudVUMeter(level: callLevel, ignite: ignite)
        }
        .padding(.vertical, -Hud.Layout.glyphInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(callFailed ? "The call’s audio dropped" : "The call’s audio is recording")
    }
}

// MARK: - From the app's state

extension RecordingSurface {
    /// The one-line warnings of a running recording, most important first.
    static func warnings(
        gate: MeetingMicrophoneGate?,
        clientName: String?,
        capture: RecordingCaptureStatus,
        safetyMessage: String?
    ) -> [Warning] {
        var warnings: [Warning] = []
        if let gate, gate.state == .unknown {
            switch gate.events.last?.source {
            case .processChanged:
                warnings.append(Warning(status: .warn, text: "Meeting app changed. Your mic is off until it’s verified."))
            case .systemInterruption:
                warnings.append(Warning(status: .warn, text: "Mac is going to sleep. Mic is off and the recording is ending."))
            default:
                if let clientName {
                    warnings.append(Warning(status: .warn, text: "Couldn’t read \(clientName)’s mute state, so your mic is kept off"))
                } else {
                    warnings.append(Warning(status: .warn, text: "Couldn’t read the mute state, so your mic is kept off"))
                }
            }
        }
        switch capture.microphone.connectionState {
        case .disconnected(let deviceName):
            warnings.append(Warning(status: .err, text: "\(deviceName) disconnected. Reconnect it or stop the recording."))
        case .recovered(let deviceName):
            warnings.append(Warning(status: .warn, text: "Microphone changed. Recording continues with \(deviceName)."))
        case .pipelineStalled:
            warnings.append(Warning(status: .err, text: "The mic’s audio stream dropped. Stopping to keep what’s recorded."))
        case .pipelineRecovered, .preparing, .ready:
            break
        }
        switch capture.systemAudio.connectionState {
        case .pipelineStalled, .disconnected:
            warnings.append(Warning(status: .err, text: "The call’s audio stream dropped. Stopping to keep what’s recorded."))
        case .pipelineRecovered, .recovered:
            warnings.append(Warning(status: .warn, text: "The call’s audio stream is back."))
        case .preparing, .ready:
            break
        }
        if let safetyMessage, !safetyMessage.isEmpty, !warnings.contains(where: { $0.text == safetyMessage }) {
            warnings.append(Warning(status: .err, text: safetyMessage))
        }
        return warnings
    }

    static func clientName(_ clientID: MeetingClientID?) -> String? {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: nil
        }
    }
}
