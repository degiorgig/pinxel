import AppKit
import CoreGraphics

@MainActor
public protocol ScreenRecordingPermission {
    var isGranted: Bool { get }
    func request()
    func openSystemSettings()
}

@MainActor
public struct SystemScreenRecordingPermission: ScreenRecordingPermission {
    public init() {}

    public var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    public func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Per test e UI test.
@MainActor
public struct GrantedScreenRecordingPermission: ScreenRecordingPermission {
    public init() {}
    public var isGranted: Bool { true }
    public func request() {}
    public func openSystemSettings() {}
}
