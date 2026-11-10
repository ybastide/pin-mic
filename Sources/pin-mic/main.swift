import CoreAudio
import Foundation

let blocked = Array(CommandLine.arguments.dropFirst())
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

func enforce() {
    guard let current = defaultInput() else { return }
    let currentName = name(current)
    guard blocked.contains(where: { currentName.localizedCaseInsensitiveContains($0) }) else { return }
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

guard !blocked.isEmpty else {
    log("usage: pin-mic <device-name-substring>...")
    exit(64)
}

var listened = address(kAudioHardwarePropertyDefaultInputDevice)
let status = AudioObjectAddPropertyListenerBlock(system, &listened, DispatchQueue.main) { _, _ in enforce() }
guard status == noErr else {
    log("cannot listen for default input changes: OSStatus \(status)")
    exit(1)
}

log("watching default input; blocked: \(blocked.joined(separator: ", "))")
enforce()
dispatchMain()
