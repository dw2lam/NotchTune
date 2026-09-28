import Testing
@testable import NotchTuneCore

/// Verifies the per-process hook skip environment contract.
/// Verifies the per-child-process hook-skip environment contract.
struct HookSkipConfigurationTests {
    /// Accepts common truthy spellings for the preferred NotchTune key.
    /// The recommended variable accepts the common truthy spellings.
    @Test
    func notchTuneSkipHooksAcceptsTruthyValues() {
        for value in ["1", "true", "TRUE", "yes", "on", " 1 "] {
            #expect(HookSkipConfiguration.shouldSkipHooks(environment: [
                HookSkipConfiguration.notchTuneSkipKey: value,
            ]))
        }
    }

    /// Keeps compatibility with existing Vibe Island-based wrappers.
    /// Existing Vibe Island wrappers keep working.
    @Test
    func legacyVibeIslandSkipAliasIsSupported() {
        #expect(HookSkipConfiguration.shouldSkipHooks(environment: [
            HookSkipConfiguration.legacyVibeIslandSkipKey: "1",
        ]))
    }

    /// Rejects unset or non-truthy values so hooks remain enabled by default.
    /// Unset or non-truthy values leave hooks enabled.
    @Test
    func skipHooksRejectsFalsyOrMissingValues() {
        for value in ["", "0", "false", "no", "off", "random"] {
            #expect(!HookSkipConfiguration.shouldSkipHooks(environment: [
                HookSkipConfiguration.notchTuneSkipKey: value,
            ]))
        }

        #expect(!HookSkipConfiguration.shouldSkipHooks(environment: [:]))
    }
}
