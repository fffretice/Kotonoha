// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Kotonoha", platforms: [.macOS(.v14)], products: [.executable(name: "Kotonoha", targets: ["Kotonoha"])], targets: [.target(name: "TranslationCore"), .executableTarget(name: "Kotonoha", dependencies: ["TranslationCore"]), .executableTarget(name: "KotonohaFixture"), .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore"])], swiftLanguageVersions: [.v5])
