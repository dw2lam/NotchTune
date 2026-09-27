import SwiftUI

/// A quiet key-cap hint ("⌘Y", "⏎") placed inside a notification-card button
/// label. It inherits the label's colour at reduced opacity and is dropped
/// entirely (via `ViewThatFits`) when the button is too narrow, so it never
/// truncates the title or changes the button's size.
struct NotificationKeyHint: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .opacity(0.4)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A button title followed by a `NotificationKeyHint` when both fit on one
/// line; otherwise the title alone.
struct NotificationKeyHintedTitle<Title: View>: View {
    let keys: String?
    @ViewBuilder let title: () -> Title

    var body: some View {
        if let keys {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    title()
                    NotificationKeyHint(keys: keys)
                }
                title()
            }
        } else {
            title()
        }
    }
}

extension NotificationKeyHintedTitle where Title == Text {
    init(_ title: String, keys: String?) {
        self.keys = keys
        self.title = { Text(title) }
    }
}
