// Tells a view whether its window is the one being used, so animations stop when nobody is watching.

import AppKit
import SwiftUI

/// Tells a view whether its window has somebody's attention, by `WindowAttention`. See Docs/app-main-window.md.
extension View {
    /// Calls `onChange` with whether this view's window is the one being used, now and whenever it changes.
    func onWindowAttentionChange(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(WindowAttentionReporter(onChange: onChange).allowsHitTesting(false))
    }
}

/// A zero-sized `NSView` whose only job is to have a `window`.
private struct WindowAttentionReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AttentionReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? AttentionReportingView)?.onChange = onChange
    }
}

private final class AttentionReportingView: NSView {
    var onChange: ((Bool) -> Void)?
    /// The last answer given, so repeated notices do not restart a running animation.
    private var lastReported: Bool?

    /// Subscribes here because a view has no window until it is placed in one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let centre = NotificationCenter.default
        centre.removeObserver(self)
        guard let window else {
            report(false)
            return
        }
        let windowNotices: [NSNotification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]
        for name in windowNotices {
            centre.addObserver(self, selector: #selector(recheck), name: name, object: window)
        }
        let applicationNotices: [NSNotification.Name] = [
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
        ]
        for name in applicationNotices {
            centre.addObserver(self, selector: #selector(recheck), name: name, object: nil)
        }
        recheck()
    }

    /// Stops the animation while this view is out of the hierarchy, as switching pages does.
    override func viewDidHide() {
        super.viewDidHide()
        report(false)
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        recheck()
    }

    @objc private func recheck() {
        let attention = WindowAttention(
            isShown: window != nil && !isHiddenOrHasHiddenAncestor,
            isKey: window?.isKeyWindow ?? false,
            isApplicationActive: NSApp.isActive,
            isApplicationHidden: NSApp.isHidden,
            isOnScreen: window?.occlusionState.contains(.visible) ?? false)
        report(attention.animates)
    }

    private func report(_ animates: Bool) {
        guard lastReported != animates else { return }
        lastReported = animates
        onChange?(animates)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
