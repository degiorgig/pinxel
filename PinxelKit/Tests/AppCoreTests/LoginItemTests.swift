import Foundation
import Testing
@testable import AppCore

@MainActor
struct LoginItemTests {
    struct Refused: Error {}

    @Test func followsTheSystemStatus() {
        #expect(!LoginItem(service: InMemoryLoginItemService(status: .disabled)).isEnabled)
        #expect(LoginItem(service: InMemoryLoginItemService(status: .enabled)).isEnabled)
    }

    @Test func turningOnRegistersTheApp() {
        let service = InMemoryLoginItemService(status: .disabled)
        let item = LoginItem(service: service)
        item.setEnabled(true)
        #expect(service.status == .enabled)
        #expect(item.isEnabled)
        #expect(item.error == nil)
    }

    @Test func turningOffUnregistersTheApp() {
        let service = InMemoryLoginItemService(status: .enabled)
        let item = LoginItem(service: service)
        item.setEnabled(false)
        #expect(service.status == .disabled)
        #expect(!item.isEnabled)
    }

    @Test func aRefusedChangeKeepsTheSwitchAsItWasAndSaysWhy() {
        let service = InMemoryLoginItemService(status: .disabled)
        service.failure = Refused()
        let item = LoginItem(service: service)
        item.setEnabled(true)
        #expect(!item.isEnabled)
        #expect(item.error != nil)

        service.failure = nil
        item.setEnabled(true)
        #expect(item.isEnabled)
        #expect(item.error == nil)
    }

    @Test func waitingForApprovalCountsAsOnAndAsksForIt() {
        let item = LoginItem(service: InMemoryLoginItemService(status: .requiresApproval))
        #expect(item.isEnabled)
        #expect(item.needsApproval)
    }

    @Test func refreshPicksUpChangesMadeInSystemSettings() {
        let service = InMemoryLoginItemService(status: .enabled)
        let item = LoginItem(service: service)
        service.status = .disabled
        item.refresh()
        #expect(!item.isEnabled)
    }

    @Test func asksAtLaunchOnlyOnceAndOnlyIfOff() {
        #expect(LoginItem(service: InMemoryLoginItemService(status: .disabled)).shouldAsk(alreadyAsked: false))
        #expect(!LoginItem(service: InMemoryLoginItemService(status: .disabled)).shouldAsk(alreadyAsked: true))
        #expect(!LoginItem(service: InMemoryLoginItemService(status: .enabled)).shouldAsk(alreadyAsked: false))
        #expect(!LoginItem(service: InMemoryLoginItemService(status: .requiresApproval)).shouldAsk(alreadyAsked: false))
    }
}
