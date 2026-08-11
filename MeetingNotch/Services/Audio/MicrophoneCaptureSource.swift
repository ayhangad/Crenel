@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class MicrophoneCaptureSource: NSObject, AudioCaptureSource, MeetingMicrophoneGateUpdating {
    let kind = AudioSourceKind.microphone
    var onLevelChange: (@Sendable (Float) -> Void)?
    var onConnectionStateChange: (@Sendable (AudioSourceConnectionState) -> Void)?

    private let captureQueue = DispatchQueue(label: "gad.MeetingNotch.audio.microphone")
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let selectedDeviceID: String?
    private let notificationCenter: NotificationCenter
    private let microphoneGateLock = NSLock()
    private var microphoneGate: MeetingMicrophoneGate?
    private var writer: SampleBufferAudioWriter?
    private var outputURL: URL?
    private var currentInput: AVCaptureDeviceInput?
    private var activeDeviceID: String?
    private var observationTokens: [NSObjectProtocol] = []

    init(
        selectedDeviceID: String? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.selectedDeviceID = selectedDeviceID
        self.notificationCenter = notificationCenter
        super.init()
    }

    func prepare(outputURL: URL) async throws {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let isAuthorized: Bool
        switch authorizationStatus {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else {
            throw RecordingCaptureError.microphonePermissionDenied
        }
        guard let device = resolvedDevice() else {
            throw RecordingCaptureError.noMicrophone
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Ses oturumu oluşturulamadı.")
        }

        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        currentInput = input
        activeDeviceID = device.uniqueID
        self.outputURL = outputURL
        writer = SampleBufferAudioWriter(outputURL: outputURL, source: kind)
        startObservingDeviceChanges()

        if let selectedDeviceID, selectedDeviceID != device.uniqueID {
            onConnectionStateChange?(.recovered(deviceName: device.localizedName))
        }
    }

    func start() async throws {
        await withCheckedContinuation { continuation in
            captureQueue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }

        guard session.isRunning else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Mikrofon akışı başlamadı.")
        }
    }

    func stop() async throws -> CapturedAudioTrack {
        stopObservingDeviceChanges()
        await stopSession()
        guard let writer, let outputURL else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Kayıt hazırlanmamış.")
        }
        defer { reset() }
        guard let firstSampleTime = try await writer.finish() else {
            throw RecordingCaptureError.sourceDidNotProduceAudio(.microphone)
        }
        return CapturedAudioTrack(
            source: .microphone,
            fileURL: outputURL,
            firstSampleTime: firstSampleTime,
            lastSampleTime: writer.lastSampleTime
        )
    }

    func cancel() async {
        stopObservingDeviceChanges()
        await stopSession()
        writer?.cancel()
        reset()
    }

    func updateMicrophoneGate(_ gate: MeetingMicrophoneGate) {
        microphoneGateLock.withLock {
            microphoneGate = gate
        }
    }

    private func stopSession() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func reset() {
        output.setSampleBufferDelegate(nil, queue: nil)
        currentInput = nil
        activeDeviceID = nil
        writer = nil
        outputURL = nil
    }

    private func resolvedDevice(excluding excludedID: String? = nil) -> AVCaptureDevice? {
        let devices = availableDevices().filter { $0.uniqueID != excludedID }
        let descriptors = devices.map { device in
            MicrophoneDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isSystemDefault: device.uniqueID == AVCaptureDevice.default(for: .audio)?.uniqueID
            )
        }
        guard let resolvedID = MicrophoneSelectionPolicy.resolvedDeviceID(
            selectedDeviceID: selectedDeviceID,
            devices: descriptors
        ) else { return nil }
        return devices.first { $0.uniqueID == resolvedID }
    }

    private func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.filter(\.isConnected)
    }

    private func startObservingDeviceChanges() {
        guard observationTokens.isEmpty else { return }
        observationTokens = [
            notificationCenter.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice,
                      device.hasMediaType(.audio) else { return }
                self?.handleDisconnectedDevice(id: device.uniqueID, name: device.localizedName)
            },
            notificationCenter.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice,
                      device.hasMediaType(.audio) else { return }
                self?.handleConnectedDevice(id: device.uniqueID)
            }
        ]
    }

    private func stopObservingDeviceChanges() {
        observationTokens.forEach(notificationCenter.removeObserver)
        observationTokens.removeAll()
    }

    private func handleDisconnectedDevice(id: String, name: String) {
        captureQueue.async { [weak self] in
            guard let self, self.activeDeviceID == id else { return }
            if let replacement = self.resolvedDevice(excluding: id),
               self.replaceInput(with: replacement) {
                self.onConnectionStateChange?(.recovered(deviceName: replacement.localizedName))
            } else {
                self.removeCurrentInput()
                self.onConnectionStateChange?(.disconnected(deviceName: name))
            }
        }
    }

    private func handleConnectedDevice(id: String) {
        captureQueue.async { [weak self] in
            guard let self else { return }
            let shouldReconnect = self.activeDeviceID == nil
                || (self.selectedDeviceID == id && self.activeDeviceID != id)
            guard shouldReconnect,
                  let replacement = self.resolvedDevice(),
                  self.replaceInput(with: replacement) else { return }
            self.onConnectionStateChange?(.recovered(deviceName: replacement.localizedName))
        }
    }

    private func replaceInput(with device: AVCaptureDevice) -> Bool {
        let previousInput = currentInput
        let replacement: AVCaptureDeviceInput
        do {
            replacement = try AVCaptureDeviceInput(device: device)
        } catch {
            return false
        }

        session.beginConfiguration()
        if let previousInput {
            session.removeInput(previousInput)
        }
        guard session.canAddInput(replacement) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            session.commitConfiguration()
            return false
        }
        session.addInput(replacement)
        session.commitConfiguration()
        currentInput = replacement
        activeDeviceID = device.uniqueID
        return true
    }

    private func removeCurrentInput() {
        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
        }
        session.commitConfiguration()
        currentInput = nil
        activeDeviceID = nil
    }
}

extension MicrophoneCaptureSource: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let gateState = microphoneGateLock.withLock {
            microphoneGate?.state ?? .closed
        }
        writer?.append(sampleBuffer, microphoneGateState: gateState)
        onLevelChange?(AudioLevelMeter.normalizedLevel(from: sampleBuffer))
    }
}
