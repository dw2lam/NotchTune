import Foundation

public struct HookRoundTripResult: Equatable, Sendable {
    /// In the order a real event travels.
    public enum Step: String, Equatable, Sendable {
        case config
        case binary
        case bridge
    }

    public enum Failure: Equatable, Sendable {
        case hookNotInConfig(path: String)
        case pluginOutdated(path: String)
        case binaryMissing(path: String)
        case binaryNotExecutable(path: String)
        /// It ran but doesn't know the ping: the app's update hasn't reached it.
        case binaryOutdated(path: String)
        case bridgeUnreachable
        case bridgeUnexpectedReply
    }

    public var failedStep: Step?
    public var failure: Failure?

    public init(failedStep: Step?, failure: Failure?) {
        self.failedStep = failedStep
        self.failure = failure
    }

    public static let passed = HookRoundTripResult(failedStep: nil, failure: nil)

    public var didPass: Bool {
        failure == nil
    }

    static func failed(_ step: Step, _ failure: Failure) -> HookRoundTripResult {
        HookRoundTripResult(failedStep: step, failure: failure)
    }
}

/// The doctor's Test hook: follows the path a real event takes, from what's in
/// the agent's config, through that exact binary, to the app's socket. No
/// agent runs, and the ping stops at the bridge, so there's no session or sound.
public enum HookRoundTripTest {
    public static func run(
        _ descriptor: HookAgentDescriptor,
        socketURL: URL = BridgeSocketLocation.currentURL(),
        deadline: TimeInterval = 3,
        fileManager: FileManager = .default
    ) -> HookRoundTripResult {
        let nonce = UUID().uuidString

        // OpenCode's plugin has no binary: it connects to the socket itself.
        guard let source = descriptor.hookSource else {
            return runPlugin(descriptor, nonce: nonce, socketURL: socketURL, deadline: deadline, fileManager: fileManager)
        }

        guard let command = HookHealthCheck.installedCommands(in: descriptor).first else {
            return .failed(.config, .hookNotInConfig(path: descriptor.configURL.path))
        }

        let binaryPath = HookHealthCheck.binaryPath(ofCommand: command)
        guard fileManager.fileExists(atPath: binaryPath) else {
            return .failed(.binary, .binaryMissing(path: binaryPath))
        }

        guard fileManager.isExecutableFile(atPath: binaryPath) else {
            return .failed(.binary, .binaryNotExecutable(path: binaryPath))
        }

        var environment = ProcessInfo.processInfo.environment
        environment["NOTCHTUNE_SOCKET_PATH"] = socketURL.path

        guard let output = BoundedProcess.run(
            executablePath: binaryPath,
            arguments: ["--source", source, "--doctor-ping", nonce],
            deadline: deadline,
            environment: environment,
            input: Data()
        ) else {
            return .failed(.bridge, .bridgeUnreachable)
        }

        switch output.status {
        case 0:
            return output.text?.contains(nonce) == true
                ? .passed
                : .failed(.binary, .binaryOutdated(path: binaryPath))
        case 3:
            return .failed(.bridge, .bridgeUnreachable)
        default:
            return .failed(.bridge, .bridgeUnexpectedReply)
        }
    }

    private static func runPlugin(
        _ descriptor: HookAgentDescriptor,
        nonce: String,
        socketURL: URL,
        deadline: TimeInterval,
        fileManager: FileManager
    ) -> HookRoundTripResult {
        let pluginPath = descriptor.configURL.path
        guard let plugin = try? Data(contentsOf: descriptor.configURL) else {
            return .failed(.config, .hookNotInConfig(path: pluginPath))
        }

        guard OpenCodePluginInstallationManager.pluginRevision(in: plugin)
                >= OpenCodePluginInstallationManager.currentPluginRevision else {
            return .failed(.config, .pluginOutdated(path: pluginPath))
        }

        let client = BridgeCommandClient(socketURL: socketURL)
        guard let response = try? client.send(.doctorPing(nonce: nonce), timeout: deadline) else {
            return .failed(.bridge, .bridgeUnreachable)
        }

        guard case .doctorPong(nonce) = response else {
            return .failed(.bridge, .bridgeUnexpectedReply)
        }

        return .passed
    }
}
