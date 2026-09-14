// What a copied string is: link, colour, path, code or text.

import Foundation

/// Works out what a copied string is; secret is asked first because it is the only costly miss.
public enum ClipKindDetector {
    /// What this text is and, for code, which language, worked out on a utility-priority task off the caller's actor.
    public static func classify(_ text: String) async -> ClipClassification {
        await classify(text, using: classification(of:))
    }

    /// `classify(_:)` with the work supplied; a continuation, not `Task.value`, so awaiting it does not raise its priority.
    static func classify(
        _ text: String, using work: @escaping @Sendable (String) -> ClipClassification
    ) async -> ClipClassification {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) { continuation.resume(returning: work(text)) }
        }
    }

    /// What this text is and, for code, which language, worked out on the calling thread.
    public static func classification(of text: String) -> ClipClassification {
        let kind = kind(of: text)
        return ClipClassification(kind: kind, language: kind == .code ? CodeLanguage.detect(text) : nil)
    }

    /// What this text is, defaulting to `.text`, the answer that costs nothing when wrong. See `Docs/performance.md`.
    public static func kind(of text: String) -> ClipKind {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        trimmed.makeContiguousUTF8()

        if SecretShapes.matches(trimmed) { return .secret }
        if ColourShape.matches(trimmed) { return .colour }
        if LinkShape.matches(trimmed) { return .link }
        // After link, because `file://` is an address; before code, because a path is punctuation.
        if PathShape.matches(trimmed) { return .filePath }
        if CodeShapes.matches(trimmed) { return .code }
        return .text
    }
}

/// A clip's kind and, when it is code, the language it is written in.
public struct ClipClassification: Sendable, Equatable {
    public let kind: ClipKind
    public let language: CodeLanguage?
}

/// A web address, and nothing that merely resembles one.
enum LinkShape {
    /// A scheme is compulsory, so `example.com` and `someone@example.com` stay text; so does `file://`.
    nonisolated(unsafe) static let address = #/(?i)https?://[^\s/?#]\S*/#

    static func matches(_ text: String) -> Bool { text.wholeMatch(of: address) != nil }
}

/// A colour in the notations a designer copies; which colour it is lives in `ColourValue`.
enum ColourShape {
    /// Three, four, six or eight hex digits behind a compulsory `#`, which keeps `dad` and `facade` off.
    nonisolated(unsafe) private static let hex =
        #/#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})/#

    /// The functional notations with no nesting inside the brackets, so a function call is not a colour.
    nonisolated(unsafe) static let functional =
        #/(?i)(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^()]+\)/#

    static func matches(_ text: String) -> Bool {
        text.wholeMatch(of: hex) != nil || text.wholeMatch(of: functional) != nil
    }
}

/// Whether a copy is worth recording at all, shared by the watcher and the store.
enum ClipContent {
    /// Whitespace and nothing else is not a clip; applications write stray newlines constantly.
    static func isWorthKeeping(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A path to a file or folder on this Mac, and only when the whole clip is the path.
enum PathShape {
    /// The prefixes that make a path a path; bare `Users/x` is how people write most things with slashes.
    static let starts = ["/", "~/", "./", "../"]

    static func matches(_ text: String) -> Bool {
        // One line: a path with a newline in it is a list or a paragraph.
        guard !text.contains(where: \.isNewline) else { return false }
        guard text.count <= 4096 else { return false }
        guard starts.contains(where: text.hasPrefix) else { return false }
        // `~` alone, or `/` alone, is a shell shorthand rather than a clip worth filing.
        guard text.count > 2 else { return false }

        // At most one space and no flag: "Application Support" passes, `./deploy.sh --force` does not.
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        guard !parts.contains(where: { $0.hasPrefix("-") }) else { return false }
        guard text.dropFirst().contains("/") || text.hasPrefix("~/") || text.hasPrefix("./")
        else { return false }

        // Characters no filesystem path carries, which code and prose use constantly.
        let forbidden: Set<Character> = ["|", "*", "<", ">", "\"", "\n", "\t"]
        return !text.contains(where: forbidden.contains)
    }
}
