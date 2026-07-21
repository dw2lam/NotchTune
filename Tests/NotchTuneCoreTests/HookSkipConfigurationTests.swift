import Testing
@testable import NotchTuneCore

/// Verifies the per-process hook skip environment contract.
/// 验证单次子进程 hook 跳过环境变量协议。
struct HookSkipConfigurationTests {
    /// Accepts common truthy spellings for the preferred NotchTune key.
    /// 推荐的新环境变量接受常见真值写法。
    @Test
    func notchTuneSkipHooksAcceptsTruthyValues() {
        for value in ["1", "true", "TRUE", "yes", "on", " 1 "] {
            #expect(HookSkipConfiguration.shouldSkipHooks(environment: [
                HookSkipConfiguration.notchTuneSkipKey: value,
            ]))
        }
    }

    /// Keeps compatibility with existing Vibe Island-based wrappers.
    /// 保留对已有 Vibe Island wrapper 的兼容。
    @Test
    func legacyVibeIslandSkipAliasIsSupported() {
        #expect(HookSkipConfiguration.shouldSkipHooks(environment: [
            HookSkipConfiguration.legacyVibeIslandSkipKey: "1",
        ]))
    }

    /// Rejects unset or non-truthy values so hooks remain enabled by default.
    /// 未设置或非真值时保持默认启用 hook。
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
