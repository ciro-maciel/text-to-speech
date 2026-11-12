// swift-tools-version:5.10
// Text to Speech for macOS, native: AppKit and SwiftUI. Davi (Phonon, on the Mac) or Rafael
// (Fish Audio, with the person's key) reads the selection aloud. Built into dist/Text to Speech.app
// by scripts/build.sh.

import PackageDescription

let package = Package(
    name: "TextToSpeech",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TextToSpeech", path: "Sources/TextToSpeech")
    ]
)
