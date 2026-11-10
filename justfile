derived_data := "build/DerivedData"
product := derived_data / "Build/Products/Release/pin-mic"
bin_dir := home_directory() / ".local/bin"
agent := "gui/" + `id -u` + "/com.zeb.pin-mic"

default: build

build:
    xcodebuild -project pin-mic.xcodeproj -scheme pin-mic -configuration Release -derivedDataPath {{ derived_data }} build

install: build
    install -m 755 {{ product }} {{ bin_dir }}/pin-mic
    if launchctl print {{ agent }} >/dev/null 2>&1; then launchctl kickstart -k {{ agent }}; else echo "{{ agent }} is not loaded; not restarting it"; fi
