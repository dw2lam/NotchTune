import Darwin
import Foundation

/// In-process replacements for the `ps` and `lsof` subprocesses the process
/// monitor used to spawn every tick, built on `sysctl` and libproc.
///
/// - `processTable()` mirrors `ps -Ao pid=,ppid=,tty=,command=`: one
///   `KERN_PROC_ALL` sysctl returns pid, parent pid, controlling tty and the
///   short command name of every process. The full command line (what `ps`
///   prints as `command`) is read per process with `KERN_PROCARGS2` — and only
///   for the processes a caller actually looks at.
/// - `openFiles(pid:)` mirrors the parts of `lsof -a -p <pid> -Fn` the monitor
///   uses: the working directory (`fcwd`) and the paths of open vnode
///   descriptors, in descriptor order.
///
/// Every entry point returns `nil` when the kernel refuses the query, so
/// callers can fall back to the subprocess they replace.
enum NativeProcessInspector {
    struct ProcessEntry: Sendable {
        var pid: pid_t
        var parentPID: pid_t
        /// Raw controlling-terminal device (`NODEV`, i.e. -1, when none).
        var ttyDevice: dev_t
        /// Controlling terminal as `ps` reports it, normalised to `/dev/ttysNNN`.
        var terminalTTY: String?
        /// Kernel short name (`p_comm`, at most 16 bytes).
        var shortName: String
    }

    struct OpenFiles: Sendable, Equatable {
        /// Absolute working directory, as `lsof` prints it for `fcwd`.
        var workingDirectory: String?
        /// Working directory first (like `lsof`), then the paths of open vnode
        /// descriptors in ascending descriptor order.
        var paths: [String]
    }

    // MARK: - Process table

    static func processTable() -> [ProcessEntry]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride

        // The table can grow between the size probe and the read; retry a few
        // times with headroom, exactly like `ps` does.
        for _ in 0..<4 {
            var byteCount = 0
            guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0, byteCount > 0 else {
                return nil
            }
            byteCount += byteCount / 8 + stride * 16

            let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<kinfo_proc>.alignment)
            defer { buffer.deallocate() }

            var readBytes = byteCount
            if sysctl(&mib, u_int(mib.count), buffer, &readBytes, nil, 0) != 0 {
                if errno == ENOMEM {
                    continue
                }
                return nil
            }

            let count = readBytes / stride
            let procs = buffer.bindMemory(to: kinfo_proc.self, capacity: count)
            var ttyNames: [dev_t: String?] = [:]
            var entries: [ProcessEntry] = []
            entries.reserveCapacity(count)

            for index in 0..<count {
                let device = procs[index].kp_eproc.e_tdev
                let tty: String?
                if let cached = ttyNames[device] {
                    tty = cached
                } else {
                    tty = ttyName(for: device)
                    ttyNames[device] = tty
                }

                let shortName = withUnsafeBytes(of: &procs[index].kp_proc.p_comm) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }

                entries.append(ProcessEntry(
                    pid: procs[index].kp_proc.p_pid,
                    parentPID: procs[index].kp_eproc.e_ppid,
                    ttyDevice: device,
                    terminalTTY: tty,
                    shortName: shortName
                ))
            }

            return entries
        }

        return nil
    }

    /// `ps` prints `??` for processes without a controlling terminal (`NODEV`)
    /// and the `devname` of the terminal otherwise.
    private static func ttyName(for device: dev_t) -> String? {
        guard device != dev_t(bitPattern: UInt32.max),
              let name = devname(device, S_IFCHR) else {
            return nil
        }

        let value = String(cString: name)
        guard !value.isEmpty, value != "??" else {
            return nil
        }

        return value.hasPrefix("/dev/") ? value : "/dev/\(value)"
    }

    // MARK: - Command lines

    /// Reads full command lines (`argv` joined by spaces, as `ps` prints the
    /// `command` column). Holds one `KERN_ARGMAX`-sized scratch buffer for its
    /// lifetime; the kernel only touches the pages it writes, so a reader per
    /// discovery pass costs one allocation.
    final class CommandLineReader {
        private let buffer: UnsafeMutableRawBufferPointer

        init() {
            var argMax: Int32 = 0
            var size = MemoryLayout<Int32>.size
            var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
            if sysctl(&mib, u_int(mib.count), &argMax, &size, nil, 0) != 0 || argMax <= 0 {
                argMax = 1 << 20
            }
            buffer = UnsafeMutableRawBufferPointer.allocate(
                byteCount: Int(argMax),
                alignment: MemoryLayout<Int32>.alignment
            )
        }

        deinit {
            buffer.deallocate()
        }

        /// `argv` joined by single spaces. When the kernel will not hand out the
        /// arguments (another user's process, e.g. the root-owned `login` that
        /// Terminal.app and Ghostty put between the app and the shell), falls
        /// back to the executable path and then to `(shortName)` — `ps` itself
        /// has elevated access and would still print the full command line.
        func commandLine(pid: pid_t, shortName: String) -> String {
            if let arguments = arguments(pid: pid), !arguments.isEmpty {
                return arguments.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let path = NativeProcessInspector.executablePath(pid: pid) {
                return path
            }

            return "(\(shortName))"
        }

        func arguments(pid: pid_t) -> [String]? {
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var size = buffer.count
            guard sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0) == 0,
                  size > MemoryLayout<Int32>.size else {
                return nil
            }

            // Layout: Int32 argc, exec path, NUL padding, argv[0..<argc], env…
            let argc = Int(buffer.load(as: Int32.self))
            guard argc > 0 else {
                return nil
            }

            var index = MemoryLayout<Int32>.size
            while index < size, buffer[index] != 0 { index += 1 }
            while index < size, buffer[index] == 0 { index += 1 }

            var arguments: [String] = []
            arguments.reserveCapacity(argc)
            while arguments.count < argc, index < size {
                let start = index
                while index < size, buffer[index] != 0 { index += 1 }
                arguments.append(String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<index]), as: UTF8.self))
                index += 1
            }

            return arguments
        }
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return nil
        }

        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    // MARK: - Open files

    /// The working directory and open vnode paths of `pid`, or `nil` when
    /// libproc denies access (fall back to `lsof`).
    static func openFiles(pid: pid_t, includeDescriptors: Bool = true) -> OpenFiles? {
        var vnodeInfo = proc_vnodepathinfo()
        let vnodeInfoSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, vnodeInfoSize) == vnodeInfoSize else {
            return nil
        }

        let cwd = cString(&vnodeInfo.pvi_cdir.vip_path)
        let workingDirectory = cwd.hasPrefix("/") ? cwd : nil
        var paths: [String] = workingDirectory.map { [$0] } ?? []

        guard includeDescriptors else {
            return OpenFiles(workingDirectory: workingDirectory, paths: paths)
        }

        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let probedBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard probedBytes > 0 else {
            return OpenFiles(workingDirectory: workingDirectory, paths: paths)
        }

        // Headroom for descriptors opened between the size probe and the read.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(probedBytes) / fdStride + 32)
        let readBytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard readBytes > 0 else {
            return OpenFiles(workingDirectory: workingDirectory, paths: paths)
        }

        let vnodePathSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        let listed = descriptors
            .prefix(Int(readBytes) / fdStride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) }
            .sorted { $0.proc_fd < $1.proc_fd }
        for descriptor in listed {
            var info = vnode_fdinfowithpath()
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, vnodePathSize) == vnodePathSize else {
                continue
            }

            let path = cString(&info.pvip.vip_path)
            if !path.isEmpty {
                paths.append(path)
            }
        }

        return OpenFiles(workingDirectory: workingDirectory, paths: paths)
    }

    private static func cString<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
