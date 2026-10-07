// swift-tools-version: 6.4
import PackageDescription

// libmysqlclient and its dependencies are linked statically from Homebrew so
// the app runs on machines without them (build-time only). Homebrew bottles
// target the current macOS, hence the deployment target. The header path is
// duplicated in Sources/CMySQL/module.modulemap (module maps can't read this).
let brew = "/opt/homebrew/opt"
let staticLibraries = [
    "\(brew)/mysql-client/lib/libmysqlclient.a",
    "\(brew)/openssl@3/lib/libssl.a",
    "\(brew)/openssl@3/lib/libcrypto.a",
    "\(brew)/zstd/lib/libzstd.a",
]

let package = Package(
    name: "SQLViewer",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "SQLViewer", targets: ["SQLViewer"]),
    ],
    targets: [
        .systemLibrary(name: "CMySQL", path: "Sources/CMySQL"),
        .target(
            name: "MySQLClient",
            dependencies: ["CMySQL"],
            linkerSettings: [
                .unsafeFlags(staticLibraries),
                // zlib, libresolv and libc++ come from the OS.
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(name: "SQLViewer", dependencies: ["MySQLClient"]),
        .testTarget(name: "MySQLClientTests", dependencies: ["MySQLClient"]),
        .testTarget(name: "SQLViewerTests", dependencies: ["SQLViewer", "MySQLClient"]),
    ]
)
