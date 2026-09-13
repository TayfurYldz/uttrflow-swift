// Decides whether a stream of keystrokes is the shortcut being pressed and released.

/// Turns keystrokes into one binding's press and release, whatever shape the binding is.
public struct HotkeyRecogniser: Sendable, Equatable {
    /// The shortcut being watched for.
    public let binding: HotkeyBinding
    /// Whether the shortcut is currently down, as far as the strokes seen say.
    public var isDown: Bool { edge.isDown }

    /// The press-and-release rule, shared with every other thing that watches a key go down.
    private var edge = HeldModifierEdge()
    /// Whether the held modifiers were used by another shortcut, which lasts until every modifier is up.
    private var isSpoiled = false

    public init(binding: HotkeyBinding) {
        self.binding = binding
    }

    /// The press or release this stroke completes, or nothing when the state did not change.
    public mutating func receive(_ stroke: KeyStroke) -> HotkeyEvent? {
        if binding.isFunctionHold { return receiveFunctionHold(stroke) }
        if binding.heldModifier != nil { return receiveModifierHold(stroke) }
        return settle(matches(stroke))
    }

    /// Fn held, read only from a flags change: an arrow key carries the same flag without being Fn.
    private mutating func receiveFunctionHold(_ stroke: KeyStroke) -> HotkeyEvent? {
        guard stroke.phase == .modifiersChanged else { return nil }
        return settle(stroke.isFunctionDown)
    }

    /// Modifiers held alone, withdrawn when a key or another modifier shows they begin a different shortcut.
    private mutating func receiveModifierHold(_ stroke: KeyStroke) -> HotkeyEvent? {
        if stroke.modifiers.isEmpty { isSpoiled = false }
        if beginsAnotherShortcut(stroke) { isSpoiled = true }
        guard isSpoiled else { return settle(matches(stroke)) }
        return edge.stopped() == nil ? nil : .cancelled
    }

    /// Whether this stroke uses the held modifiers for something else: a key typed, or a modifier the binding lacks.
    private func beginsAnotherShortcut(_ stroke: KeyStroke) -> Bool {
        if stroke.phase == .down, !stroke.modifiers.isEmpty { return true }
        return !stroke.modifiers.isSubset(of: heldModifiers)
    }

    /// A release owed because watching stopped mid-hold, or nothing when nothing was held.
    public mutating func finish() -> HotkeyEvent? { settle(false) }

    /// Whether this stroke is the binding held right now.
    private func matches(_ stroke: KeyStroke) -> Bool {
        guard !binding.modifiers.isEmpty || binding.heldModifier != nil else { return false }
        // A held modifier is down when exactly its own modifiers are, and nothing else.
        if binding.heldModifier != nil, binding.modifiers.isEmpty {
            return stroke.modifiers == modifiersOfHeldKey && !stroke.isFunctionDown
        }
        if binding.heldModifier != nil { return stroke.modifiers == binding.modifiers }
        // A combination is down while its key is down and exactly its modifiers are held.
        return stroke.phase == .down && stroke.keyCode == binding.keyCode
            && stroke.modifiers == binding.modifiers
    }

    /// The modifiers a held binding is made of, its own key's included.
    private var heldModifiers: Set<HotkeyModifier> {
        binding.modifiers.union(modifiersOfHeldKey)
    }

    /// The modifier a held binding's own key code is, so ⌘ held alone reads as ⌘.
    private var modifiersOfHeldKey: Set<HotkeyModifier> {
        guard let named = HotkeyBinding.modifier(ofKeyCode: binding.keyCode) else { return [] }
        return [named]
    }

    /// Reports only a change, since a flags change says what is held rather than what moved.
    private mutating func settle(_ downNow: Bool) -> HotkeyEvent? {
        edge.flagsChanged(isDownNow: downNow)
    }
}
