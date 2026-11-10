# pin-mic

Keeps Bluetooth audio devices from becoming the default input on macOS.

When a Bluetooth speaker or headset that has a microphone connects, macOS makes it the default
input. As soon as an app opens that input, the device drops from A2DP to the headset profile and
playback quality collapses (crackling, mono, low bandwidth). macOS reapplies this on every
reconnect and has no setting to turn it off.

`pin-mic` watches the default input device through a CoreAudio property listener. Whenever the
default input's name contains one of the substrings given on its command line, it switches the
default input to the built-in microphone. It is event-driven, so it uses no CPU while idle.

```
pin-mic <device-name-substring>...
pin-mic Pebble
```

Matching is case-insensitive. The built-in microphone is found by transport type, so its
localized name does not matter.

## Build and install

Requires Xcode and [just](https://github.com/casey/just).

```
just build      # Release build into build/DerivedData
just install    # build, copy to ~/.local/bin/pin-mic, restart the LaunchAgent if loaded
```

To run it at login, install the LaunchAgent once:

```
cp com.zeb.pin-mic.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.zeb.pin-mic.plist
launchctl print gui/$(id -u)/com.zeb.pin-mic | grep -E 'state|pid'
```

The device substrings are the `ProgramArguments` after the binary path in
`com.zeb.pin-mic.plist`. After changing them, copy the plist again, then `launchctl bootout` and
`bootstrap` the agent.

Each switch is logged to `~/Library/Logs/pin-mic.log`.

## Uninstall

```
launchctl bootout gui/$(id -u)/com.zeb.pin-mic
rm ~/Library/LaunchAgents/com.zeb.pin-mic.plist ~/.local/bin/pin-mic
```

## Limitations

Only the system default input is pinned. An app that selects the Bluetooth microphone itself
(Zoom, Meet, and so on) still uses it, so set those apps to the built-in microphone.

## Project

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec, and
`pin-mic.xcodeproj` is generated from it. Run `xcodegen generate` after editing `project.yml`.
