import XCTest
@testable import Lumina

final class PowerManagerTests: XCTestCase {

    func testInitialPolicy() throws {
        let pm = PowerManager()
        // On a typical dev machine this should be normal (or throttled if thermally stressed)
        let isNormalOrThrottled = pm.currentPolicy == .normal || {
            if case .throttled = pm.currentPolicy { return true }
            return false
        }()
        XCTAssertTrue(isNormalOrThrottled)
    }

    func testManualPauseAndResume() throws {
        let pm = PowerManager()

        pm.pauseManually()
        if case .paused(let reason) = pm.currentPolicy {
            XCTAssertEqual(reason, .manual)
        } else {
            XCTFail("Expected paused state after manual pause")
        }

        pm.resumeManually()
        let isNormalOrThrottled = pm.currentPolicy == .normal || {
            if case .throttled = pm.currentPolicy { return true }
            return false
        }()
        XCTAssertTrue(isNormalOrThrottled)
    }

    func testFullscreenPauseRespected() throws {
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
