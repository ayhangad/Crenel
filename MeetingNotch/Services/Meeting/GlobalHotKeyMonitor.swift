import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyMonitor {
    private static let signature: OSType = 0x4D4E_4D47 // MNMG
    private static let identifier: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: (@MainActor () -> Void)?

    @discardableResult
    func start(action: @escaping @MainActor () -> Void) -> Bool {
        stop()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .invoke()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            stop()
            return false
        }

        var hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        action = nil
    }

    private func invoke() {
        guard let action else { return }
        Task { @MainActor in action() }
    }

    deinit {
        stop()
    }
}
