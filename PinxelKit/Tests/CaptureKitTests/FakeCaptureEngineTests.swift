import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct FakeCaptureEngineTests {
    @Test func snapshotHasDisplayAndWindow() async throws {
        let snapshot = try await FakeCaptureEngine().snapshot(excludingBundleIdentifier: "com.degiorgi.pinxel")
        #expect(snapshot.displays.count == 1)
        #expect(snapshot.displays[0].image.width == 1600)
        #expect(snapshot.windows.map(\.title) == ["Finestra finta"])
        #expect(snapshot.scale(for: snapshot.windows[0]) == 2)
    }

    @Test func fakeAreaComposesRedSquare() async throws {
        let snapshot = try await FakeCaptureEngine().snapshot(excludingBundleIdentifier: "")
        let result = try #require(CaptureComposer.compose(CGRect(x: 100, y: 100, width: 200, height: 150), from: snapshot.displays))
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 400 && pixels.height == 300)
        #expect(pixels.pixel(x: 200, y: 150) == RGBA8(r: 255, g: 0, b: 0))
    }

    @Test func missingWindowThrowsWindowNotFound() async {
        await #expect(throws: CaptureError.windowNotFound) {
            try await FakeCaptureEngine().captureWindow(999, includeShadow: true)
        }
    }

    @Test func windowCaptureReturnsImage() async throws {
        let image = try await FakeCaptureEngine().captureWindow(7, includeShadow: false)
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func grantedPermission() {
        #expect(GrantedScreenRecordingPermission().isGranted)
    }
}
