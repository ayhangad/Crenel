import CoreAudio
import Foundation

struct AudioProcessSnapshot: Identifiable, Equatable, Hashable, Sendable {
    let audioObjectID: AudioObjectID
    let processID: Int32
    let bundleIdentifier: String?
    let isRunningInput: Bool
    let isRunningOutput: Bool

    var id: AudioObjectID { audioObjectID }
    var hasActiveIO: Bool { isRunningInput || isRunningOutput }
}

protocol AudioProcessSnapshotReading: Sendable {
    func readSnapshots() throws -> [AudioProcessSnapshot]
}

protocol AudioProcessMonitoring: Sendable {
    func start(
        onUpdate: @escaping @Sendable ([AudioProcessSnapshot]) async -> Void
    ) async
    func refresh() async
    func stop() async
}

enum CoreAudioProcessMonitorError: Error, Equatable {
    case propertyRead(selector: AudioObjectPropertySelector, status: OSStatus)
}

struct CoreAudioProcessSnapshotReader: AudioProcessSnapshotReading {
    func readSnapshots() throws -> [AudioProcessSnapshot] {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        guard status == noErr else {
            throw CoreAudioProcessMonitorError.propertyRead(
                selector: address.mSelector,
                status: status
            )
        }

        let count = Int(propertySize) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var objectIDs = Array(repeating: AudioObjectID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &objectIDs
        )
        guard status == noErr else {
            throw CoreAudioProcessMonitorError.propertyRead(
                selector: address.mSelector,
                status: status
            )
        }

        return objectIDs.compactMap(snapshot).sorted {
            if $0.processID == $1.processID {
                return $0.audioObjectID < $1.audioObjectID
            }
            return $0.processID < $1.processID
        }
    }

    private func snapshot(for objectID: AudioObjectID) -> AudioProcessSnapshot? {
        guard let processID: pid_t = try? scalar(
            objectID: objectID,
            selector: kAudioProcessPropertyPID
        ) else {
            return nil
        }
        let isRunningInput: UInt32 = (try? scalar(
            objectID: objectID,
            selector: kAudioProcessPropertyIsRunningInput
        )) ?? 0
        let isRunningOutput: UInt32 = (try? scalar(
            objectID: objectID,
            selector: kAudioProcessPropertyIsRunningOutput
        )) ?? 0

        return AudioProcessSnapshot(
            audioObjectID: objectID,
            processID: Int32(processID),
            bundleIdentifier: bundleIdentifier(for: objectID),
            isRunningInput: isRunningInput != 0,
            isRunningOutput: isRunningOutput != 0
        )
    }

    private func scalar<T: FixedWidthInteger>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> T {
        var address = propertyAddress(selector)
        var value: T = 0
        var propertySize = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &propertySize,
            &value
        )
        guard status == noErr else {
            throw CoreAudioProcessMonitorError.propertyRead(
                selector: selector,
                status: status
            )
        }
        return value
    }

    private func bundleIdentifier(for objectID: AudioObjectID) -> String? {
        var address = propertyAddress(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &propertySize,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

actor CoreAudioProcessMonitor: AudioProcessMonitoring {
    typealias UpdateHandler = @Sendable ([AudioProcessSnapshot]) async -> Void

    private let reader: any AudioProcessSnapshotReading
    private let pollingInterval: Duration?
    private var updateHandler: UpdateHandler?
    private var pollingTask: Task<Void, Never>?
    private var latestSnapshots: [AudioProcessSnapshot]?

    init(
        reader: any AudioProcessSnapshotReading = CoreAudioProcessSnapshotReader(),
        pollingInterval: Duration? = .seconds(1)
    ) {
        self.reader = reader
        self.pollingInterval = pollingInterval
    }

    func start(onUpdate: @escaping UpdateHandler) async {
        stop()
        updateHandler = onUpdate
        await refresh()

        guard let pollingInterval else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pollingInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        // Refresh call controls even when HAL IO flags do not change (mute is not IO).
        // A read failure must invalidate stale open-microphone evidence.
        let snapshots = (try? reader.readSnapshots()) ?? []
        latestSnapshots = snapshots
        await updateHandler?(snapshots)
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        updateHandler = nil
        latestSnapshots = nil
    }
}
