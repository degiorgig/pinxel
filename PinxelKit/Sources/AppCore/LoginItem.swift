import Foundation
import Observation
import ServiceManagement

public enum LoginItemStatus: Sendable {
    case enabled, disabled
    /// Registered, but the user still has to allow it in System Settings ▸ General ▸ Login Items.
    case requiresApproval
}

@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Pinxel itself as a login item: works without a helper app, in the App Sandbox too.
@MainActor
public final class SystemLoginItemService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// For tests and UI tests, which must not register the app being tested.
@MainActor
public final class InMemoryLoginItemService: LoginItemService {
    public var status: LoginItemStatus
    public var failure: (any Error)?

    public init(status: LoginItemStatus = .disabled) { self.status = status }

    public func register() throws {
        if let failure { throw failure }
        status = .enabled
    }

    public func unregister() throws {
        if let failure { throw failure }
        status = .disabled
    }
}

/// The "Open at login" switch. The state belongs to macOS, which the user can also change from System Settings:
/// `refresh()` reads it again.
@MainActor
@Observable
public final class LoginItem {
    public private(set) var status: LoginItemStatus
    /// Why the last change did not happen, to show next to the switch.
    public private(set) var error: String?
    @ObservationIgnored private let service: any LoginItemService

    public init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    public var isEnabled: Bool { status != .disabled }
    public var needsApproval: Bool { status == .requiresApproval }

    public func setEnabled(_ enabled: Bool) {
        do {
            try enabled ? service.register() : service.unregister()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    public func refresh() { status = service.status }

    /// The question at launch: once, and not if the app already opens at login.
    public func shouldAsk(alreadyAsked: Bool) -> Bool { !alreadyAsked && status == .disabled }
}
