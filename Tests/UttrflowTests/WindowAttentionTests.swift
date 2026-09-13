// Tests for when the home page's demonstration is allowed to move.

import Testing
import UttrflowCore

@testable import Uttrflow

/// The card moves in the window being used and nowhere else, since a visible window is not a watched one.
@Suite("Whether a window has somebody's attention")
struct WindowAttentionTests {
    /// The main window on Home, key, in the active app, on screen.
    private let inUse = WindowAttention(
        isShown: true, isKey: true, isApplicationActive: true, isApplicationHidden: false,
        isOnScreen: true)

    @Test("moves while its window is key in the active app and Home is showing")
    func movesWhenInUse() {
        #expect(inUse.animates)
    }

    @Test("stays still when another window of the app has the keyboard")
    func stillWhenNotKey() {
        var attention = inUse
        attention.isKey = false

        #expect(!attention.animates)
    }

    @Test("stays still when partly visible behind another app's window")
    func stillWhenPartlyCovered() {
        var attention = inUse
        attention.isKey = false
        attention.isApplicationActive = false

        #expect(!attention.animates)
    }

    @Test("stays still when fully covered")
    func stillWhenCovered() {
        var attention = inUse
        attention.isOnScreen = false

        #expect(!attention.animates)
    }

    @Test("stays still when the app is hidden")
    func stillWhenHidden() {
        var attention = inUse
        attention.isApplicationHidden = true

        #expect(!attention.animates)
    }

    @Test("stays still once a different page is chosen")
    func stillOffHome() {
        var attention = inUse
        attention.isShown = false

        #expect(!attention.animates)
    }

    @Test("stays still under Reduce Motion, even in the window being used")
    func stillUnderReduceMotion() {
        var attention = inUse
        attention.motion = MotionBudget(reducesMotion: true)

        #expect(!attention.animates)
    }

    @Test("stays still in Low Power Mode, even in the window being used")
    func stillInLowPowerMode() {
        var attention = inUse
        attention.motion = MotionBudget(energy: EnergyConditions(isLowPowerMode: true))

        #expect(!attention.animates)
    }

    @Test("stays still at serious thermal pressure, even in the window being used")
    func stillWhenHot() {
        var attention = inUse
        attention.motion = MotionBudget(energy: EnergyConditions(thermal: .serious))

        #expect(!attention.animates)
    }
}
