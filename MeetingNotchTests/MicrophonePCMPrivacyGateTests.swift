import AVFoundation
import XCTest
@testable import MeetingNotch

final class MicrophonePCMPrivacyGateTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testClosedAndUnknownBuffersAreZeroFilledWithoutDroppingFrames() throws {
        let gate = MicrophonePCMPrivacyGate(sampleRate: sampleRate)
        let closed = makeBuffer(value: 0.75, frames: 480)
        let unknown = makeBuffer(value: 0.5, frames: 480)

        XCTAssertNil(gate.enqueue(closed, state: .closed))
        let first = try XCTUnwrap(gate.enqueue(unknown, state: .unknown))
        let second = try XCTUnwrap(gate.flush())

        XCTAssertEqual(first.frameLength, 480)
        XCTAssertEqual(second.frameLength, 480)
        XCTAssertEqual(peak(first), 0)
        XCTAssertEqual(peak(second), 0)
    }

    func testOpeningGateUsesShortFadeInAndThenPreservesSignal() throws {
        let gate = MicrophonePCMPrivacyGate(sampleRate: sampleRate, fadeDuration: 0.005)
        let buffer = makeBuffer(value: 1, frames: 480)

        gate.enqueue(buffer, state: .open)
        let output = try XCTUnwrap(gate.flush())
        let samples = try XCTUnwrap(output.floatChannelData?[0])

        XCTAssertGreaterThan(samples[0], 0)
        XCTAssertLessThan(samples[0], 0.01)
        XCTAssertEqual(samples[239], 1, accuracy: 0.001)
        XCTAssertEqual(samples[479], 1, accuracy: 0.001)
    }

    func testClosingGateFadesPreviousOpenTailAndZerosClosedBuffer() throws {
        let gate = MicrophonePCMPrivacyGate(sampleRate: sampleRate, fadeDuration: 0.005)
        let open = makeBuffer(value: 1, frames: 480)
        let closed = makeBuffer(value: 1, frames: 480)

        gate.enqueue(open, state: .open)
        let fadedOpen = try XCTUnwrap(gate.enqueue(closed, state: .closed))
        let silentClosed = try XCTUnwrap(gate.flush())
        let samples = try XCTUnwrap(fadedOpen.floatChannelData?[0])

        XCTAssertEqual(samples[239], 1, accuracy: 0.001)
        XCTAssertLessThan(samples[479], 0.001)
        XCTAssertEqual(peak(silentClosed), 0)
    }

    func testRapidTransitionsPreserveTotalFrameCount() throws {
        let gate = MicrophonePCMPrivacyGate(sampleRate: sampleRate)
        let states: [MeetingMicrophoneState] = [
            .closed, .open, .unknown, .open, .closed
        ]
        var outputFrameCount = 0

        for state in states {
            if let ready = gate.enqueue(makeBuffer(value: 0.8, frames: 240), state: state) {
                outputFrameCount += Int(ready.frameLength)
            }
        }
        outputFrameCount += Int(try XCTUnwrap(gate.flush()).frameLength)

        XCTAssertEqual(outputFrameCount, states.count * 240)
    }

    private func makeBuffer(value: Float, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = value
        }
        return buffer
    }

    private func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return .infinity }
        return (0..<Int(buffer.frameLength)).reduce(0) {
            max($0, abs(samples[$1]))
        }
    }
}
