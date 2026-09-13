// Tests for which endings of a field's life finish its value.

import Testing
import UttrflowCore

@testable import UttrflowPredictCapture

@Suite("Which endings finish a value")
struct CommitPolicyTests {
    /// A field reading carrying only the application, which is all the policy asks about.
    private func reading(_ bundleIdentifier: String) -> FieldReading {
        FieldReading(bundleIdentifier: bundleIdentifier, role: "AXTextArea")
    }

    /// A message not sent is a draft the user abandoned, and it used to be learned like one they sent.
    @Test(
        "learns a chat line only when Return sent it",
        arguments: [CommitReason.focusLeft, .applicationDeactivated, .wentIdle])
    func refusesAnUnsentChatLine(reason: CommitReason) {
        let policy = CommitPolicy.whereReturnSends

        #expect(policy.admits(reason, in: reading("com.tinyspeck.slackmacgap")) == false)
        #expect(policy.admits(.returnPressed, in: reading("com.tinyspeck.slackmacgap")))
    }

    /// The rule a terminal already had, for its own reason: a shell rewrites the line on the way out.
    @Test("keeps the terminal's rule")
    func keepsTheTerminalRule() {
        let policy = CommitPolicy.whereReturnSends

        #expect(policy.admits(.focusLeft, in: reading("com.apple.terminal")) == false)
        #expect(policy.admits(.returnPressed, in: reading("com.apple.terminal")))
    }

    /// Somewhere the words stay put, every ending is a value: a document is not sent anywhere.
    @Test(
        "learns from a document however the field ended",
        arguments: [CommitReason.returnPressed, .focusLeft, .applicationDeactivated, .wentIdle])
    func learnsFromADocument(reason: CommitReason) {
        #expect(CommitPolicy.whereReturnSends.admits(reason, in: reading("com.apple.textedit")))
        #expect(CommitPolicy.whereReturnSends.admits(reason, in: reading("com.apple.dt.xcode")))
    }

    @Test("asks the destination table which applications are conversations")
    func readsTheDestinationTable() {
        #expect(CommitPolicy.sendsOnReturn("com.tinyspeck.slackmacgap"))
        #expect(CommitPolicy.sendsOnReturn("com.apple.MobileSMS"))
        #expect(CommitPolicy.sendsOnReturn("com.apple.terminal"))
        #expect(CommitPolicy.sendsOnReturn("com.apple.textedit") == false)
    }
}
