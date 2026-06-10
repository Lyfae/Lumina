@testable import Lumina

#if canImport(Testing)
import Testing

@MainActor
struct PowerManagerTests {

    /// True when the policy is .normal or .throttled — the two states a healthy,
    /// unpaused dev machine can legitimately be in.
    private func isNormalOrThrottled(_ pm: PowerManager) -> Bool {
        if pm.currentPolicy == .normal { return true }
        if case .throttled = pm.currentPolicy { return true }
        return false
    }

    @Test func initialPolicy() {
        let pm = PowerManager()
        #expect(isNormalOrThrottled(pm))
    }

    @Test func manualPauseAndResume() {
        let pm = PowerManager()

        pm.pauseManually()
        if case .paused(let reason) = pm.currentPolicy {
            #expect(reason == .manual)
        } else {
            Issue.record("Expected paused state after manual pause")
        }

        pm.resumeManually()
        #expect(isNormalOrThrottled(pm))
    }

    @Test func fullscreenPauseRespected() {
        let pm = PowerManager()
        pm.respectFullscreenApps = true

        pm.updateFullscreenObscured(true)
        if case .paused(let reason) = pm.currentPolicy {
            #expect(reason == .fullscreenApp)
        } else {
            Issue.record("Expected fullscreen pause")
        }

        pm.updateFullscreenObscured(false)
        // After un-obscured we re-evaluate; it should no longer be the fullscreen pause reason
        if case .paused(let reason) = pm.currentPolicy {
            #expect(reason != .fullscreenApp)
        }
    }
}
#elseif canImport(XCTest)
import XCTest

@MainActor
final class PowerManagerTests: XCTestCase {

    /// True when the policy is .normal or .throttled — the two states a healthy,
    /// unpaused dev machine can legitimately be in.
    private func isNormalOrThrottled(_ pm: PowerManager) -> Bool {
        if pm.currentPolicy == .normal { return true }
        if case .throttled = pm.currentPolicy { return true }
        return false
    }

    func testInitialPolicy() {
        let pm = PowerManager()
        XCTAssertTrue(isNormalOrThrottled(pm))
    }

    func testManualPauseAndResume() {
        let pm = PowerManager()

        pm.pauseManually()
        if case .paused(let reason) = pm.currentPolicy {
            XCTAssertEqual(reason, .manual)
        } else {
            XCTFail("Expected paused state after manual pause")
        }

        pm.resumeManually()
        XCTAssertTrue(isNormalOrThrottled(pm))
    }

    func testFullscreenPauseRespected() {
        let pm = PowerManager()
        pm.respectFullscreenApps = true

        pm.updateFullscreenObscured(true)
        if case .paused(let reason) = pm.currentPolicy {
            XCTAssertEqual(reason, .fullscreenApp)
        } else {
            XCTFail("Expected fullscreen pause")
        }

        pm.updateFullscreenObscured(false)
        // After un-obscured we re-evaluate; it should no longer be the fullscreen pause reason
        if case .paused(let reason) = pm.currentPolicy {
            XCTAssertNotEqual(reason, .fullscreenApp)
        }
    }
}
#endif
