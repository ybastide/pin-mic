import CoreAudio
import Darwin
import Foundation

let usage = """
    usage: pin-mic                              show whether pin-mic is running, and what it blocks
           pin-mic <device-name-substring>...   watch the default input and pin the built-in mic
           pin-mic -l | --list                  list Bluetooth input devices
           pin-mic -h | --help                  show this help
    """

let arguments = Array(CommandLine.arguments.dropFirst())
let system = AudioObjectID(kAudioObjectSystemObject)

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func defaultInput() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
    return id
}

func setDefaultInput(_ id: AudioDeviceID) -> OSStatus {
    var addr = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = id
    return AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
}

func name(_ id: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
    return value.takeRetainedValue() as String
}

func transport(_ id: AudioDeviceID) -> UInt32 {
    var addr = address(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
}

func hasInput(_ id: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
}

func devices() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func isBluetooth(_ id: AudioDeviceID) -> Bool {
    let type = transport(id)
    return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
}

func matches(_ deviceName: String, _ patterns: [String]) -> Bool {
    patterns.contains(where: { deviceName.localizedCaseInsensitiveContains($0) })
}

func enforce(_ blocked: [String]) {
    guard let current = defaultInput() else { return }
    let currentName = name(current)
    guard matches(currentName, blocked) else { return }
    guard let target = devices().first(where: { transport($0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) }) else {
        log("\(currentName) is the default input but no built-in input device was found")
        return
    }
    let status = setDefaultInput(target)
    if status == noErr {
        log("switched default input from \(currentName) to \(name(target))")
    } else {
        log("failed to switch default input from \(currentName): OSStatus \(status)")
    }
}

func executablePath(_ pid: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
}

func processArguments(_ pid: pid_t) -> [String]? {
    var argmax: Int32 = 0
    var size = MemoryLayout<Int32>.size
    var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
    guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: Int(argmax))
    size = buffer.count
    mib = [CTL_KERN, KERN_PROCARGS2, pid]
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
    let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
    var index = MemoryLayout<Int32>.size
    while index < size && buffer[index] != 0 { index += 1 }
    while index < size && buffer[index] == 0 { index += 1 }
    var result: [String] = []
    while result.count < argc && index < size {
        let start = index
        while index < size && buffer[index] != 0 { index += 1 }
        result.append(String(decoding: buffer[start..<index], as: UTF8.self))
        index += 1
    }
    return result
}

func watchers() -> [(pid: pid_t, blocked: [String])] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) * 2)
    let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard found > 0 else { return [] }
    return pids.prefix(Int(found)).compactMap { pid in
        guard pid != getpid(),
              let path = executablePath(pid),
              (path as NSString).lastPathComponent == "pin-mic",
              let args = processArguments(pid)?.dropFirst(),
              !args.isEmpty,
              !args.contains(where: { $0.hasPrefix("-") })
        else { return nil }
        return (pid, Array(args))
    }
}

func inputDevices() -> [AudioDeviceID] {
    devices().filter(hasInput)
}

func listBluetooth() {
    let running = watchers().flatMap(\.blocked)
    let current = defaultInput()
    let bluetooth = inputDevices().filter(isBluetooth)
    guard !bluetooth.isEmpty else {
        print("no Bluetooth input devices connected")
        return
    }
    for id in bluetooth {
        let deviceName = name(id)
        var tags: [String] = []
        if id == current { tags.append("default input") }
        if matches(deviceName, running) { tags.append("blocked") }
        print(tags.isEmpty ? deviceName : "\(deviceName) [\(tags.joined(separator: ", "))]")
    }
}

func showStatus() -> Int32 {
    let running = watchers()
    guard !running.isEmpty else {
        print("pin-mic is not running")
        return 1
    }
    let inputs = inputDevices()
    for watcher in running {
        print("pin-mic is running (pid \(watcher.pid)), blocking: \(watcher.blocked.joined(separator: ", "))")
        let matched = inputs.map(name).filter { matches($0, watcher.blocked) }
        print(matched.isEmpty
            ? "  no matching input device connected"
            : "  matching input devices: \(matched.joined(separator: ", "))")
    }
    if let current = defaultInput() {
        print("default input: \(name(current))")
    }
    return 0
}

func watch(_ blocked: [String]) -> Never {
    var listened = address(kAudioHardwarePropertyDefaultInputDevice)
    let status = AudioObjectAddPropertyListenerBlock(system, &listened, DispatchQueue.main) { _, _ in enforce(blocked) }
    guard status == noErr else {
        log("cannot listen for default input changes: OSStatus \(status)")
        exit(1)
    }
    log("watching default input; blocked: \(blocked.joined(separator: ", "))")
    enforce(blocked)
    dispatchMain()
}

func usageError() -> Never {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}

switch arguments {
case []:
    exit(showStatus())
case ["-h"], ["--help"]:
    print(usage)
case ["-l"], ["--list"]:
    listBluetooth()
case _ where arguments.contains(where: { $0.hasPrefix("-") }):
    usageError()
default:
    watch(arguments)
}
