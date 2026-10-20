import Darwin

/// Reads process details with libproc and sysctl. Works fully for the
/// current user's processes; for others, fields we may not read come back nil.
public struct ProcessInspector: ProcessInspecting {
    public init() {}

    public func identity(pid: Int32) -> ProcessIdentity? {
        bsdInfo(pid).map(Self.identity)
    }

    public func details(pid: Int32) -> ProcessDetails? {
        guard let info = bsdInfo(pid) else { return nil }
        return ProcessDetails(
            identity: Self.identity(info),
            executablePath: path(pid),
            arguments: arguments(pid),
            workingDirectory: workingDirectory(pid),
            uid: info.pbi_uid,
            parentPid: Int32(info.pbi_ppid)
        )
    }

    private static func identity(_ info: proc_bsdinfo) -> ProcessIdentity {
        ProcessIdentity(
            pid: Int32(info.pbi_pid),
            startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        )
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private func path(_ pid: Int32) -> String? {
        var buf = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf[..<Int(n)], as: UTF8.self)
    }

    private func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    /// KERN_PROCARGS2 layout: argc (Int32), exec path, NUL padding, argv[0..argc), env…
    private func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }

        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }   // exec path
        while i < size, buf[i] == 0 { i += 1 }   // padding

        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
