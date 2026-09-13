// The clipboard demonstration's clock and its choice of arrangement, both pure functions.

import CoreGraphics
import Foundation

/// Everything the demonstration draws at one instant, as a function of the clock alone.
struct ClipboardDemonstrationPhase: Equatable {
    let keysAreDown: Bool
    let returnIsDown: Bool
    /// 0 while the panel is absent, 1 once it is fully there.
    let panel: Double
    let selected: Int
    let highlight: Double
    /// How much of the chosen line has been typed into the document, 0 to 1.
    let typed: Double

    /// How long the whole story takes: long enough to read the pasted line, short enough to see it happen.
    static let loop: Double = 8

    /// The whole animation as a function of the clock, so the page can redraw under it without a stutter.
    static func at(_ date: Date) -> Self {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        func at(
            keys: Bool = false, enter: Bool = false, panel: Double, row: Int,
            highlight: Double, typed: Double = 0
        ) -> Self {
            Self(
                keysAreDown: keys, returnIsDown: enter, panel: panel, selected: row,
                highlight: highlight, typed: typed)
        }
        switch t {
        // Someone is part-way through writing something. Nothing is happening yet.
        case ..<1.0: return at(panel: 0, row: 0, highlight: 0)
        // The keys go down and the panel arrives with them.
        case ..<1.9: return at(keys: true, panel: eased((t - 1.0) / 0.9), row: 0, highlight: 0)
        // It settles, and the first line is under the cursor.
        case ..<2.5: return at(panel: 1, row: 0, highlight: 1)
        // Down, and down again — which is how it is actually used.
        case ..<3.1: return at(panel: 1, row: 1, highlight: 1)
        case ..<3.9: return at(panel: 1, row: 2, highlight: 1)
        // Return. The panel goes.
        case ..<4.3: return at(enter: true, panel: 1, row: 2, highlight: 1)
        case ..<4.9:
            return at(panel: 1 - eased((t - 4.3) / 0.6), row: 2, highlight: 1)
        // And the words land where the cursor was, which is the whole point of the thing.
        case ..<typingEnds:
            return at(panel: 0, row: 2, highlight: 0, typed: eased((t - typingStarts) / 1.0))
        // Long enough to read what arrived before it resets.
        default: return at(panel: 0, row: 2, highlight: 0, typed: 1)
        }
    }

    /// Seconds into the loop at which the chosen line starts arriving in the document.
    static let typingStarts: Double = 4.9

    /// Seconds into the loop by which the whole line has arrived.
    static let typingEnds: Double = 5.9

    /// How many characters of a line `length` long are in the document at this instant.
    func typedCount(of length: Int) -> Int {
        Int((Double(length) * typed).rounded())
    }

    /// Whether the caret follows the arriving words, which it does only while they are arriving.
    var showsCaret: Bool { typed > 0 && typed < 1 }

    /// The seconds into the loop at which each further character of a line `length` long appears.
    static func characterArrivals(length: Int) -> [Double] {
        guard length > 0 else { return [] }
        return (1...length).map { count in
            let typed = (Double(count) - 0.5) / Double(length)
            return typingStarts + (1 - pow(1 - typed, 1.0 / 3))
        }
    }

    /// What the card shows while nobody is using its window: the panel open, the address row chosen.
    static let resting = at(Date(timeIntervalSinceReferenceDate: 3.5))

    /// Ease-out, so things arrive rather than snapping.
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}

/// The instants at which the demonstration's drawing changes, so its clock does not wake on every display frame.
struct ClipboardDemonstrationMoments: Sequence, IteratorProtocol {
    /// How far apart instants are while the panel moves, at the fastest display's refresh rate.
    static let frame: Double = 1.0 / 120

    /// How far past a boundary an instant lands, so the state drawn is the one after it.
    static let nudge: Double = 0.001

    /// Seconds into the loop at which the drawing jumps from one still state to the next.
    static let steps: [Double] = [1.0, 1.9, 2.5, 3.1, 3.9, 4.3, 4.9, 5.9, ClipboardDemonstrationPhase.loop]

    /// Seconds into the loop during which the panel moves: rising, then going.
    static let motion: [Range<Double>] = [1.0..<1.9, 4.3..<4.9]

    /// Every boundary in one loop, the characters of the typed line included, in order.
    private let changes: [Double]
    private var loopStart: Date
    private var offset: Double
    private var pending: Date?
    private let isStill: Bool

    /// Starts at `start` for a typed line `typedLength` long; a still card gets that one instant and nothing after it.
    init(from start: Date, typedLength: Int, isStill: Bool = false) {
        let loop = ClipboardDemonstrationPhase.loop
        changes = (Self.steps + ClipboardDemonstrationPhase.characterArrivals(length: typedLength)).sorted()
        offset = start.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        loopStart = start.addingTimeInterval(-offset)
        pending = start
        self.isStill = isStill
    }

    mutating func next() -> Date? {
        if let first = pending {
            pending = nil
            return first
        }
        guard !isStill else { return nil }
        offset = change(after: offset)
        if offset >= ClipboardDemonstrationPhase.loop {
            loopStart = loopStart.addingTimeInterval(ClipboardDemonstrationPhase.loop)
            offset -= ClipboardDemonstrationPhase.loop
        }
        return loopStart.addingTimeInterval(offset)
    }

    /// The first instant after `offset` seconds into the loop at which anything drawn is different.
    func change(after offset: Double) -> Double {
        if let moving = Self.motion.first(where: { $0.lowerBound <= offset && offset < $0.upperBound }) {
            let step = offset + Self.frame
            return step < moving.upperBound ? step : moving.upperBound + Self.nudge
        }
        var boundary = ClipboardDemonstrationPhase.loop
        for change in changes.reversed() where change > offset - Self.nudge / 2 {
            boundary = change
        }
        return boundary + Self.nudge
    }
}

/// Which of the demonstration's two arrangements a given width can hold. See Docs/app-main-window.md.
enum ClipboardDemonstrationArrangement: Equatable {
    case sideBySide(explanationWidth: CGFloat)
    case stacked
}

/// The card's fixed dimensions, and the width at which it stops being able to stand side by side.
enum ClipboardDemonstrationMetrics {
    /// The card's own inset, inside the surface.
    static let padding: CGFloat = 17

    /// Between the words and the document, in the side-by-side arrangement.
    static let columnSpacing: CGFloat = 22

    /// Wide enough for the pasted line to arrive unwrapped: 373 points of text and ten of padding a side.
    static let documentWidth: CGFloat = 400

    /// Tall enough for the panel to sit over the document without either being clipped.
    static let stageHeight: CGFloat = 172

    /// The narrowest the words may be beside the document before the stacked arrangement reads better.
    static let explanationMinimumWidth: CGFloat = 360

    /// The widest the words are allowed to run, so a long line stays comfortable to read.
    static let explanationMaximumWidth: CGFloat = 460

    /// Chooses the arrangement from the width the card is offered, once, rather than on every frame.
    static func arrangement(forOfferedWidth width: CGFloat) -> ClipboardDemonstrationArrangement {
        let forWords = width - padding * 2 - columnSpacing - documentWidth
        guard forWords >= explanationMinimumWidth else { return .stacked }
        return .sideBySide(explanationWidth: min(forWords, explanationMaximumWidth))
    }
}
