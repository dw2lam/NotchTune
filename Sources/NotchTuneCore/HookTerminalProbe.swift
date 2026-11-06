import Darwin
import Foundation

/// Terminal lookups for the hook CLI, which runs on the agent's critical path.
enum HookTerminalProbe {
    /// A focused-terminal query gets this long. It normally answers in tens of
    /// milliseconds; a pending Automation prompt never answers at all, and
    /// the agent would freeze on every tool call waiting for it.
    static let locatorDeadline: TimeInterval = 0.3

    /// The hook's own stdin is the payload pipe, and Claude Code runs hooks in
    /// a session with no controlling terminal, so the TTY has to come from the
    /// nearest ancestor that has one. In process: no helper to wait on.
    static func currentTTY() -> String? {
        if isatty(STDIN_FILENO) == 1, let name = ttyname(STDIN_FILENO) {
            return String(cString: name)
        }

        return ancestorTTY(startingAt: getppid(), lookup: processInfo(pid:))
    }

    static func ancestorTTY(
        startingAt pid: pid_t,
        maxDepth: Int = 8,
        lookup: (pid_t) -> (parent: pid_t, tty: String?)?
    ) -> String? {
        var current = pid
        for _ in 0..<maxDepth where current > 1 {
            guard let info = lookup(current) else {
                return nil
            }

            if let tty = info.tty {
                return tty
            }

            current = info.parent
        }

        return nil
    }

    private static func processInfo(pid: pid_t) -> (parent: pid_t, tty: String?)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else {
            return (info.kp_eproc.e_ppid, nil)
        }

        return (info.kp_eproc.e_ppid, "/dev/\(String(cString: name))")
    }

    /// Runs a focused-terminal AppleScript under the deadline. `nil` means no
    /// answer in time; the session keeps the target it already has.
    static func osascript(_ script: String) -> String? {
        BoundedProcess.run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script],
            deadline: locatorDeadline
        ).flatMap { output in
            output.status == 0 ? output.text : nil
        }
    }
}
