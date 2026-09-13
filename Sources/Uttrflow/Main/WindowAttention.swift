// Whether a window is the one somebody is using, decided from what AppKit reports about it.

/// What AppKit reports about a view's window at one moment, reduced to what decides whether it may move.
struct WindowAttention: Equatable {
    /// Whether the view is in a window and not hidden, which it is not once its page is switched away.
    var isShown: Bool

    /// Whether the window takes the keyboard, which only the active application's front window does.
    var isKey: Bool

    /// Whether this application is the active one.
    var isApplicationActive: Bool

    /// Whether this application is hidden with Command-H.
    var isApplicationHidden: Bool

    /// Whether any part of the window is on screen, from `NSWindow.occlusionState`.
    var isOnScreen: Bool

    /// Moves only in the window being used; a window merely visible behind another app stays still.
    var animates: Bool {
        isShown && isKey && isApplicationActive && !isApplicationHidden && isOnScreen
    }
}
