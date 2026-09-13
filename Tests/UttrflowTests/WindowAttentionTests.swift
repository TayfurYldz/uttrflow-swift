// Tests for when the home page's demonstration is allowed to move.

import Testing

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
}
