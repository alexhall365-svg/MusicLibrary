// swift-tools-version: 5.9

// Swift Playgrounds app package. Open this folder in Swift Playgrounds on iPad
// (or in Xcode) to build and run the app. The same sources are also used by the
// XcodeGen project (project.yml) for CI and command-line builds.
//
// If you rename the app, change `name` and `bundleIdentifier` here AND
// APP_DISPLAY_NAME / APP_BUNDLE_ID in Config/App.xcconfig.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Quire",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Quire",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.musiclibrary",
            teamIdentifier: "",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .music
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
