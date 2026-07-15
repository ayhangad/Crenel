import AppKit

struct NotchScreenDescriptor: Equatable {
    let id: UInt32
    let frame: CGRect
    let hasNotch: Bool
    let isMain: Bool

    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

enum NotchScreenSelectionPolicy {
    static func startupScreen(
        from screens: [NotchScreenDescriptor]
    ) -> NotchScreenDescriptor? {
        screens.first(where: { $0.hasNotch && $0.isMain })
            ?? screens.first(where: \.hasNotch)
            ?? screens.first(where: \.isMain)
            ?? screens.first
    }

    static func presentationScreen(
        from screens: [NotchScreenDescriptor],
        pointerLocation: CGPoint
    ) -> NotchScreenDescriptor? {
        screens.first(where: { $0.contains(pointerLocation) })
            ?? startupScreen(from: screens)
    }
}

@MainActor
final class NotchScreenResolver {
    func startupScreen() -> NSScreen? {
        resolve(
            descriptor: NotchScreenSelectionPolicy.startupScreen(from: descriptors)
        )
    }

    func presentationScreen() -> NSScreen? {
        resolve(
            descriptor: NotchScreenSelectionPolicy.presentationScreen(
                from: descriptors,
                pointerLocation: NSEvent.mouseLocation
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
                isMain: screen == NSScreen.main
            )
        }
    }

    private func resolve(descriptor: NotchScreenDescriptor?) -> NSScreen? {
        guard let descriptor else { return NSScreen.main ?? NSScreen.screens.first }
        return NSScreen.screens.first(where: { screenID($0) == descriptor.id })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
