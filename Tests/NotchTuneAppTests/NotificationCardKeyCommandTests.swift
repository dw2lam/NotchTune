import AppKit
import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Pure mapping tests for `NotificationCardKeyCommand.resolve`.
struct NotificationCardKeyCommandTests {
    private enum Code {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let y: UInt16 = 16
        static let n: UInt16 = 45
        static let j: UInt16 = 38
        static let r: UInt16 = 15
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let one: UInt16 = 18
        static let nine: UInt16 = 25
        static let zero: UInt16 = 29
    }

    private func key(
        _ code: UInt16,
        _ chars: String,
        _ modifiers: NotificationCardKeyInput.Modifiers = [],
        isRepeat: Bool = false
    ) -> NotificationCardKeyInput {
        NotificationCardKeyInput(keyCode: code, characters: chars, modifiers: modifiers, isRepeat: isRepeat)
    }

    private func resolve(
        _ input: NotificationCardKeyInput,
        _ card: NotificationCardKind,
        editing: Bool = false,
        cardAge: TimeInterval = 5,
        sinceUnmapped: TimeInterval = .infinity
    ) -> NotificationCardKeyCommand? {
        NotificationCardKeyCommand.resolve(
            input,
            context: .init(
                card: card,
                isEditingText: editing,
                cardAge: cardAge,
                timeSinceUnmappedKey: sinceUnmapped
            )
        )
    }

    private let approval = NotificationCardKind.approval(supportsAlwaysAllow: true)
    private let approvalNoAlways = NotificationCardKind.approval(supportsAlwaysAllow: false)
    private let completion = NotificationCardKind.completion(hasReply: true)
    private let completionNoReply = NotificationCardKind.completion(hasReply: false)

    // MARK: Approval

    @Test
    func approvalCommandShortcuts() {
        #expect(resolve(key(Code.y, "y", .command), approval) == .allowOnce)
        #expect(resolve(key(Code.n, "n", .command), approval) == .deny)
        // charactersIgnoringModifiers keeps Shift, so ⇧⌘Y reports "Y".
        #expect(resolve(key(Code.y, "Y", [.command, .shift]), approval) == .alwaysAllow)
    }

    @Test
    func alwaysAllowOnlyWhenTheCardOffersIt() {
        #expect(resolve(key(Code.y, "Y", [.command, .shift]), approvalNoAlways) == nil)
        #expect(resolve(key(Code.y, "y", .command), approvalNoAlways) == .allowOnce)
    }

    @Test
    func bareLettersAndForeignChordsNeverAct() {
        #expect(resolve(key(Code.y, "y"), approval) == nil)
        #expect(resolve(key(Code.n, "n"), approval) == nil)
        #expect(resolve(key(Code.y, "y", [.command, .option]), approval) == nil)
        #expect(resolve(key(Code.y, "y", [.command, .control]), approval) == nil)
        #expect(resolve(key(Code.n, "N", [.command, .shift]), approval) == nil)
    }

    @Test
    func returnAllowsOnlyOnceArmed() {
        #expect(resolve(key(Code.returnKey, "\r"), approval, cardAge: 5) == .allowOnce)
        #expect(resolve(key(Code.keypadEnter, "\u{3}"), approval, cardAge: 5) == .allowOnce)
        // Card just appeared: a stray Return meant for the terminal is ignored.
        #expect(resolve(key(Code.returnKey, "\r"), approval, cardAge: 0.2) == nil)
        // User was typing into the panel a moment ago.
        #expect(resolve(key(Code.returnKey, "\r"), approval, cardAge: 5, sinceUnmapped: 0.3) == nil)
        // ⌘Y is deliberate and not gated.
        #expect(resolve(key(Code.y, "y", .command), approval, cardAge: 0.05, sinceUnmapped: 0.05) == .allowOnce)
    }

    @Test
    func escapeDismissesAndNeverDenies() {
        #expect(resolve(key(Code.escape, "\u{1b}"), approval) == .dismiss)
        #expect(resolve(key(Code.escape, "\u{1b}"), .question) == .dismiss)
        #expect(resolve(key(Code.escape, "\u{1b}"), completion) == .dismiss)
        #expect(resolve(key(Code.escape, "\u{1b}", .shift), approval) == nil)
    }

    // MARK: Question

    @Test
    func commandDigitsPickNumberedOptions() {
        #expect(resolve(key(Code.one, "1", .command), .question) == .pickOption(0))
        #expect(resolve(key(Code.nine, "9", .command), .question) == .pickOption(8))
        #expect(resolve(key(Code.zero, "0", .command), .question) == nil)
        #expect(resolve(key(Code.one, "1"), .question) == nil)
    }

    @Test
    func commandDigitsFallBackToKeyCodeOnShiftedNumberRows() {
        // AZERTY: the "1" key reports "&" without Shift.
        #expect(resolve(key(Code.one, "&", .command), .question) == .pickOption(0))
    }

    @Test
    func returnSubmitsQuestion() {
        #expect(resolve(key(Code.returnKey, "\r"), .question, cardAge: 0) == .submit)
    }

    @Test
    func digitsDoNothingOnOtherCards() {
        #expect(resolve(key(Code.one, "1", .command), approval) == nil)
        #expect(resolve(key(Code.one, "1", .command), completion) == nil)
    }

    // MARK: Completion

    @Test
    func completionShortcuts() {
        #expect(resolve(key(Code.returnKey, "\r"), completion, cardAge: 0) == .jump)
        #expect(resolve(key(Code.j, "j", .command), completion) == .jump)
        #expect(resolve(key(Code.r, "r", .command), completion) == .openReply)
        #expect(resolve(key(Code.leftBracket, "[", .command), completion) == .previous)
        #expect(resolve(key(Code.rightBracket, "]", .command), completion) == .next)
    }

    @Test
    func replyShortcutOnlyWhenReplyIsAvailable() {
        #expect(resolve(key(Code.r, "r", .command), completionNoReply) == nil)
        #expect(resolve(key(Code.j, "j", .command), completionNoReply) == .jump)
    }

    @Test
    func approvalKeysDoNothingOnCompletion() {
        #expect(resolve(key(Code.y, "y", .command), completion) == nil)
        #expect(resolve(key(Code.n, "n", .command), completion) == nil)
    }

    // MARK: Text editing / repeats

    @Test
    func everyKeyBelongsToAFocusedTextField() {
        #expect(resolve(key(Code.returnKey, "\r"), completion, editing: true) == nil)
        #expect(resolve(key(Code.escape, "\u{1b}"), completion, editing: true) == nil)
        #expect(resolve(key(Code.one, "1", .command), .question, editing: true) == nil)
        #expect(resolve(key(Code.returnKey, "\r"), .question, editing: true) == nil)
    }

    @Test
    func keyRepeatsAreIgnored() {
        #expect(resolve(key(Code.y, "y", .command, isRepeat: true), approval) == nil)
        #expect(resolve(key(Code.returnKey, "\r", isRepeat: true), completion) == nil)
    }

    // MARK: Card kind / event conversion

    @Test
    func cardKindFollowsSessionPhase() {
        var session = AgentSession(
            id: "s",
            title: "Codex · s",
            tool: .codex,
            phase: .waitingForApproval,
            summary: "",
            updatedAt: Date(timeIntervalSince1970: 0),
            permissionRequest: PermissionRequest(title: "Bash", summary: "ls", affectedPath: "", toolName: "Bash")
        )
        #expect(NotificationCardKind(session: session, replyAvailable: false) == .approval(supportsAlwaysAllow: true))

        session.permissionRequest?.toolName = nil
        #expect(NotificationCardKind(session: session, replyAvailable: false) == .approval(supportsAlwaysAllow: false))

        session.phase = .waitingForAnswer
        #expect(NotificationCardKind(session: session, replyAvailable: false) == .question)

        session.phase = .completed
        #expect(NotificationCardKind(session: session, replyAvailable: true) == .completion(hasReply: true))

        session.phase = .running
        #expect(NotificationCardKind(session: session, replyAvailable: true) == nil)
    }

    @Test
    func eventModifierFlagsMapToInputModifiers() {
        let input = OverlayPanelController.keyInput(
            keyCode: Code.y,
            characters: "Y",
            modifierFlags: [.command, .shift, .capsLock, .numericPad],
            isRepeat: true
        )
        #expect(input.modifiers == [.command, .shift])
        #expect(input.isRepeat)
        #expect(input.characters == "Y")

        let option = OverlayPanelController.keyInput(
            keyCode: Code.y, characters: "y", modifierFlags: [.command, .option], isRepeat: false
        )
        #expect(option.modifiers == [.command, .option])
    }

    @Test
    func alwaysAllowActionAddsSessionRuleForTool() {
        guard case let .allowWithUpdates(updates) = ApprovalAction.alwaysAllow(toolName: "Bash") else {
            Issue.record("expected allowWithUpdates")
            return
        }
        #expect(updates == [
            .addRules(destination: .session, rules: [ClaudePermissionRuleValue(toolName: "Bash")], behavior: .allow),
        ])
    }
}
