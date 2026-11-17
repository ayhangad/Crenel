import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing {
    var isConfigured: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
struct LaunchAtLoginService: LaunchAtLoginServicing {
    var isConfigured: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            true
        case .notFound, .notRegistered:
            false
        @unknown default:
            false
        }
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard !isConfigured else { return }
            try SMAppService.mainApp.register()
        } else {
            guard isConfigured else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
