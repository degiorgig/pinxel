import CoreGraphics
import Testing
@testable import CaptureKit

@MainActor
struct ScrollCaptureSystemTests {
    @Test func sourceRectIsRelativeToTheDisplay() {
        let display = DisplayInfo(id: 2, frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080), scale: 2)
        let rect = CGRect(x: 1500, y: 100, width: 300, height: 400)
        #expect(ScreenCaptureKitFrameSource.sourceRect(for: rect, on: display) == CGRect(x: 60, y: 300, width: 300, height: 400))
        #expect(ScreenCaptureKitFrameSource.pixelSize(for: rect, on: display) == (600, 800))
    }

    @Test func fixedPermissionReportsItsValue() {
        #expect(FixedAccessibilityPermission(isGranted: true).isGranted)
        #expect(!FixedAccessibilityPermission(isGranted: false).isGranted)
    }
}
