import Foundation
import NotchTuneCore

/// Which notification card is on screen, as far as keyboard control cares.
enum NotificationCardKind: Equatable, Sendable {
    /// Permission request. `supportsAlwaysAllow` mirrors the "Always Allow"
    /// button, which only exists when the request names a tool.
    case approval(supportsAlwaysAllow: Bool)
    /// Structured or freeform question.
    case question
    /// Completion toast. `hasReply` mirrors the toast's Reply button.
    case completion(hasReply: Bool)

    init?(session: AgentSession, replyAvailable: Bool) {
        switch session.phase {
        case .waitingForApproval:
            self = .approval(supportsAlwaysAllow: session.permissionRequest?.toolName != nil)
        case .waitingForAnswer:
            self = .question
        case .completed:
            self = .completion(hasReply: replyAvailable)
        case .running:
            return nil
        }
    }
}

/// A key press, reduced to the parts the mapper needs so it can be built
/// from an `NSEvent` in the app and by hand in tests.
struct NotificationCardKeyInput: Equatable, Sendable {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    /// Hardware key code (`kVK_*`). Used for Return / Esc and as a digit
    /// fallback on layouts where the number row needs Shift (AZERTY).
    var keyCode: UInt16
    /// `charactersIgnoringModifiers`, so ⌘Y resolves by the key's letter on
    /// the active layout, like a menu shortcut.
    var characters: String
    var modifiers: Modifiers = []
    var isRepeat = false
}

/// What a key press does to the notification card on screen.
///
/// | Card        | Keys                                   | Command                |
/// |-------------|----------------------------------------|------------------------|
/// | approval    | ⌘Y / Return                            | allow once             |
/// | approval    | ⌘N                                     | deny                   |
/// | approval    | ⌘⇧Y (tool-scoped requests only)        | always allow           |
/// | question    | ⌘1 … ⌘9                                | pick numbered option   |
/// | question    | Return                                 | submit (if enabled)    |
/// | completion  | Return / ⌘J                            | jump                   |
/// | completion  | ⌘R (reply available only)              | open reply             |
/// | completion  | ⌘[ / ⌘]                                | previous / next toast  |
/// | any         | Esc                                    | dismiss (never denies) |
enum NotificationCardKeyCommand: Equatable, Sendable {
    case allowOnce
    case deny
    case alwaysAllow
    /// Zero-based index of the numbered option (⌘1 → 0).
    case pickOption(Int)
    case submit
    case jump
    case openReply
    case previous
    case next
    case dismiss

    /// Context the mapper needs beyond the key itself.
    struct Context: Equatable, Sendable {
        var card: NotificationCardKind
        /// A text field in the card (reply / "Other" field) is being edited.
        /// Every key then belongs to the field: it already owns Return
        /// (submit, IME-safe) and Esc.
        var isEditingText = false
        /// How long the card has been on screen.
        var cardAge: TimeInterval = .infinity
        /// Time since the last key the panel saw that was NOT a card command,
        /// i.e. the user was typing something else (the panel is made key on
        /// open, so keystrokes meant for their terminal can land here).
        var timeSinceUnmappedKey: TimeInterval = .infinity
    }

    /// A bare Return approving a tool call must be deliberate: it is ignored
    /// until the card has been visible this long and the user has not been
    /// typing into the panel for this long. ⌘Y is always deliberate.
    static let bareReturnApprovalArmDelay: TimeInterval = 0.8

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        /// kVK_ANSI_1 … kVK_ANSI_9 in digit order.
        static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    /// Resolves a key press to a card command, or `nil` to let the key
    /// through untouched.
    static func resolve(_ input: NotificationCardKeyInput, context: Context) -> NotificationCardKeyCommand? {
        guard !input.isRepeat, !context.isEditingText else {
            return nil
        }

        // Option / Control chords are never ours.
        guard input.modifiers.isDisjoint(with: [.option, .control]) else {
            return nil
        }

        let isCommand = input.modifiers.contains(.command)
        let isShift = input.modifiers.contains(.shift)
        let key = input.characters.lowercased()

        if !isCommand {
            guard !isShift else { return nil }
            switch input.keyCode {
            case KeyCode.escape:
                return .dismiss
            case KeyCode.returnKey, KeyCode.keypadEnter:
                return returnCommand(context: context)
            default:
                return nil
            }
        }

        switch context.card {
        case let .approval(supportsAlwaysAllow):
            switch (key, isShift) {
            case ("y", false): return .allowOnce
            case ("y", true): return supportsAlwaysAllow ? .alwaysAllow : nil
            case ("n", false): return .deny
            default: return nil
            }

        case .question:
            // Shift is tolerated so ⌘1 still works where the number row is
            // shifted (AZERTY reports "&" unshifted; keyCode disambiguates).
            if let index = digitIndex(for: input) {
                return .pickOption(index)
            }
            return nil

        case let .completion(hasReply):
            guard !isShift else { return nil }
            switch key {
            case "j": return .jump
            case "r": return hasReply ? .openReply : nil
            case "[": return .previous
            case "]": return .next
            default: return nil
            }
        }
    }

    private static func returnCommand(context: Context) -> NotificationCardKeyCommand? {
        switch context.card {
        case .approval:
            guard context.cardAge >= bareReturnApprovalArmDelay,
                  context.timeSinceUnmappedKey >= bareReturnApprovalArmDelay else {
                return nil
            }
            return .allowOnce
        case .question:
            return .submit
        case .completion:
            return .jump
        }
    }

    private static func digitIndex(for input: NotificationCardKeyInput) -> Int? {
        if let scalar = input.characters.unicodeScalars.first,
           input.characters.unicodeScalars.count == 1,
           ("1"..."9").contains(scalar) {
            return Int(scalar.value) - Int(("1" as Unicode.Scalar).value)
        }
        return KeyCode.digits.firstIndex(of: input.keyCode)
    }
}

extension ApprovalAction {
    /// The "Always Allow (<tool>)" action: allow now and add a session-scoped
    /// allow rule for the tool. Shared by the card button and ⌘⇧Y.
    static func alwaysAllow(toolName: String) -> ApprovalAction {
        let rule = ClaudePermissionRuleValue(toolName: toolName)
        let update = ClaudePermissionUpdate.addRules(
            destination: .session,
            rules: [rule],
            behavior: .allow
        )
        return .allowWithUpdates([update])
    }
}

/// Posted to hand a keyboard command to a card view that owns the state it
/// acts on (question selections, the toast's reply field). `object` is the
/// session ID; `userInfo[commandKey]` is the `NotificationCardKeyCommand`.
extension Notification.Name {
    static let notificationCardKeyCommand = Notification.Name("NotchTune.notificationCardKeyCommand")
}

enum NotificationCardKeyCommandBus {
    static let commandKey = "command"

    @MainActor
    static func post(_ command: NotificationCardKeyCommand, sessionID: String) {
        NotificationCenter.default.post(
            name: .notificationCardKeyCommand,
            object: sessionID,
            userInfo: [commandKey: command]
        )
    }

    static func command(from notification: Notification, sessionID: String) -> NotificationCardKeyCommand? {
        guard notification.object as? String == sessionID else { return nil }
        return notification.userInfo?[commandKey] as? NotificationCardKeyCommand
    }
}
