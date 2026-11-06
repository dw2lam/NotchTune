import Testing
@testable import NotchTuneApp

@MainActor
struct AppNoticeTests {
    @Test
    func theSameProblemDoesNotReplaceTheNoticeOnScreen() {
        let model = AppModel()
        let first = AppNotice(message: "Couldn't jump to Ghostty.")
        model.post(first)
        model.post(AppNotice(message: "Couldn't jump to Ghostty."))
        #expect(model.notice?.id == first.id)

        let other = AppNotice(message: "Hooks couldn't be installed.")
        model.post(other)
        #expect(model.notice?.id == other.id)

        model.dismissNotice()
        #expect(model.notice == nil)
    }
}
