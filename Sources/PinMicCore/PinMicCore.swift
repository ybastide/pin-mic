import Foundation

public enum Command: Equatable, Sendable {
    case status
    case list
    case help
    case watch([String])
    case usageError
}

public func parse(_ arguments: [String]) -> Command {
    switch arguments {
    case []: .status
    case ["-h"], ["--help"]: .help
    case ["-l"], ["--list"]: .list
    case _ where arguments.contains(where: { $0.hasPrefix("-") }): .usageError
    default: .watch(arguments)
    }
}

public func matches(_ deviceName: String, _ patterns: [String]) -> Bool {
    patterns.contains(where: { deviceName.localizedCaseInsensitiveContains($0) })
}

/// Decodes a `KERN_PROCARGS2` buffer: an `Int32` argc, the executable path, NUL padding, then
/// argc NUL-terminated arguments (followed by the environment, which is ignored).
public func parseProcessArguments(_ buffer: [UInt8]) -> [String]? {
    let header = MemoryLayout<Int32>.size
    guard buffer.count > header else { return nil }
    let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard argc >= 0 else { return nil }
    var index = header
    while index < buffer.count && buffer[index] != 0 { index += 1 }
    while index < buffer.count && buffer[index] == 0 { index += 1 }
    var result: [String] = []
    while result.count < argc && index < buffer.count {
        let start = index
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        result.append(String(decoding: buffer[start..<index], as: UTF8.self))
        index += 1
    }
    return result.count == argc ? result : nil
}
