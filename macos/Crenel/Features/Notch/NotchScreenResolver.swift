import AppKit

struct NotchScreenDescriptor: Equatable {
    let id: UInt32
    let frame: CGRect
    let hasNotch: Bool
    let isMain: Bool
    /// Stable across restarts and reconnections (the display ID is not).
    var uuid: String?

    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

enum NotchScreenSelectionPolicy {
    /// The screen the user dragged the notch to, when it is connected; otherwise the
    /// built-in notch.
    static func startupScreen(
        from screens: [NotchScreenDescriptor],
        preferredUUID: String? = nil
    ) -> NotchScreenDescriptor? {
        if let preferredUUID, let preferred = screens.first(where: { $0.uuid == preferredUUID }) {
            return preferred
        }
        return screens.first(where: { $0.hasNotch && $0.isMain })
            ?? screens.first(where: \.hasNotch)
            ?? screens.first(where: \.isMain)
            ?? screens.first
    }

    static func presentationScreen(
        from screens: [NotchScreenDescriptor],
        pointerLocation: CGPoint,
        preferredUUID: String? = nil
    ) -> NotchScreenDescriptor? {
        screens.first(where: { $0.contains(pointerLocation) })
            ?? startupScreen(from: screens, preferredUUID: preferredUUID)
    }

    /// Where a dragged notch lands: the screen under the pointer, or the nearest one.
    static func dropScreen(
        from screens: [NotchScreenDescriptor],
        pointerLocation: CGPoint
    ) -> NotchScreenDescriptor? {
        screens.first(where: { $0.contains(pointerLocation) })
            ?? screens.min(by: { distance($0.frame, pointerLocation) < distance($1.frame, pointerLocation) })
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

@MainActor
final class NotchScreenResolver {
    static let preferredDisplayKey = "notch.preferredDisplayUUID"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The display the user dragged the notch to; nil means the built-in notch.
    var preferredDisplayUUID: String? {
        defaults.string(forKey: Self.preferredDisplayKey)
    }

    /// Remembers the screen the notch was dropped on. The built-in notch is the default,
    /// so choosing it clears the preference.
    func rememberPreferredScreen(_ screen: NSScreen) {
        let startup = NotchScreenSelectionPolicy.startupScreen(from: descriptors)
        if let startup, startup.id == screenID(screen) {
            defaults.removeObject(forKey: Self.preferredDisplayKey)
        } else if let uuid = displayUUID(screen) {
            defaults.set(uuid, forKey: Self.preferredDisplayKey)
        }
    }

    func startupScreen() -> NSScreen? {
        resolve(
            descriptor: NotchScreenSelectionPolicy.startupScreen(
                from: descriptors,
                preferredUUID: preferredDisplayUUID
            )
        )
    }

    func dropScreen(at point: CGPoint) -> NSScreen? {
        resolve(descriptor: NotchScreenSelectionPolicy.dropScreen(from: descriptors, pointerLocation: point))
    }

    func presentationScreen() -> NSScreen? {
        resolve(
            descriptor: NotchScreenSelectionPolicy.presentationScreen(
                from: descriptors,
                pointerLocation: NSEvent.mouseLocation,
                preferredUUID: preferredDisplayUUID
            )
        )
    }

    func availableScreen(matching screen: NSScreen?) -> NSScreen? {
        guard let id = screen.flatMap(screenID) else {
            return startupScreen()
        }
        return NSScreen.screens.first(where: { screenID($0) == id }) ?? startupScreen()
    }

    func isSameScreen(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhsID = lhs.flatMap(screenID), let rhsID = rhs.flatMap(screenID) else {
            return lhs == nil && rhs == nil
        }
        return lhsID == rhsID
    }

    func hasPhysicalNotch(_ screen: NSScreen) -> Bool {
        screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    private var descriptors: [NotchScreenDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let id = screenID(screen) else { return nil }
            return NotchScreenDescriptor(
                id: id,
                frame: screen.frame,
                hasNotch: hasPhysicalNotch(screen),
                isMain: screen == NSScreen.main,
                uuid: displayUUID(screen)
            )
        }
    }

    private func resolve(descriptor: NotchScreenDescriptor?) -> NSScreen? {
        guard let descriptor else { return NSScreen.main ?? NSScreen.screens.first }
        return NSScreen.screens.first(where: { screenID($0) == descriptor.id })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func displayUUID(_ screen: NSScreen) -> String? {
        guard let id = screenID(screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func screenID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
