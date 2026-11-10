import PinMicCore
import Testing

@Suite struct ParseTests {
    @Test func noArgumentsShowsStatus() {
        #expect(parse([]) == .status)
    }

    @Test(arguments: ["-h", "--help"])
    func help(flag: String) {
        #expect(parse([flag]) == .help)
    }

    @Test(arguments: ["-l", "--list"])
    func list(flag: String) {
        #expect(parse([flag]) == .list)
    }

    @Test func substringsWatch() {
        #expect(parse(["Pebble"]) == .watch(["Pebble"]))
        #expect(parse(["Pebble", "AirPods Pro"]) == .watch(["Pebble", "AirPods Pro"]))
    }

    @Test(arguments: [["--bogus"], ["-s"], ["-l", "Pebble"], ["Pebble", "-h"], ["-h", "-l"]])
    func usageErrors(arguments: [String]) {
        #expect(parse(arguments) == .usageError)
    }
}

@Suite struct MatchTests {
    @Test func caseInsensitiveSubstring() {
        #expect(matches("Creative Pebble X Plus", ["pebble"]))
        #expect(matches("Creative Pebble X Plus", ["AirPods", "PEBBLE"]))
    }

    @Test func noMatch() {
        #expect(!matches("Micro MacBook Air", ["Pebble"]))
        #expect(!matches("Creative Pebble X Plus", []))
    }
}

@Suite struct ProcessArgumentsTests {
    func buffer(argc: Int32, path: String, padding: Int, strings: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(path.utf8) + [UInt8](repeating: 0, count: padding)
        for string in strings { bytes += Array(string.utf8) + [0] }
        return bytes
    }

    @Test func decodesArgumentsAndSkipsEnvironment() {
        let bytes = buffer(
            argc: 2,
            path: "/Users/zeb/.local/bin/pin-mic",
            padding: 5,
            strings: ["/Users/zeb/.local/bin/pin-mic", "Pebble", "HOME=/Users/zeb", "PATH=/usr/bin"]
        )
        #expect(parseProcessArguments(bytes) == ["/Users/zeb/.local/bin/pin-mic", "Pebble"])
    }

    @Test func keepsArgumentsWithSpacesAndUnicode() {
        let bytes = buffer(argc: 3, path: "/bin/pin-mic", padding: 1, strings: ["pin-mic", "AirPods Pro", "Écouteurs"])
        #expect(parseProcessArguments(bytes) == ["pin-mic", "AirPods Pro", "Écouteurs"])
    }

    @Test func emptyArgumentIsKept() {
        let bytes = buffer(argc: 2, path: "/bin/pin-mic", padding: 1, strings: ["pin-mic", ""])
        #expect(parseProcessArguments(bytes) == ["pin-mic", ""])
    }

    @Test func truncatedBufferIsRejected() {
        let bytes = buffer(argc: 3, path: "/bin/pin-mic", padding: 1, strings: ["pin-mic", "Pebble"])
        #expect(parseProcessArguments(bytes) == nil)
    }

    @Test func bufferShorterThanHeaderIsRejected() {
        #expect(parseProcessArguments([]) == nil)
        #expect(parseProcessArguments([1, 0, 0, 0]) == nil)
    }

    @Test func negativeArgcIsRejected() {
        #expect(parseProcessArguments(buffer(argc: -1, path: "/bin/pin-mic", padding: 1, strings: [])) == nil)
    }
}
