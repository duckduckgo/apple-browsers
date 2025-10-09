// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import PackageDescription
import Foundation

let package = Package(
    name: "CommonObjCExtensions",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "BWIntegration", targets: ["BWIntegration"]),
        .library(name: "CommonObjCExtensions", targets: ["CommonObjCExtensions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/OpenSSL-XCFramework", exact: "3.3.2000")
    ],
    targets: [
        .target(
            name: "BWIntegration",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL-XCFramework")
            ],
            sources: [
                "BWEncryption.m",
                "BWEncryptionOutput.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "CommonObjCExtensions",
            dependencies: [],
            sources: [
                "NSException+Catch.m",
                "NSObject+valueForIvar.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: isXcode ? [
                // Use dynamically determined clang runtime library path
                // This is a workaround to allow the compiler to find the clang runtime library
                // when building with code coverage enabled, otherwise the build will fail with:
                // ld: library not found for -lclang_rt.profile_osx
                //
                // For more details, see https://forums.swift.org/t/compiler-code-coverage-need-help/68075
                .unsafeFlags([
                    "-L\(clangLibPath())",
                    "-lclang_rt.profile_osx"
                ], .when(platforms: [.macOS]))
            ] : []
        )
    ]
)

var isXcode: Bool {
    ProcessInfo.processInfo.environment["__CFBundleIdentifier"]?.contains("com.apple.dt.Xcode") == true
}

// Dynamically determine clang runtime library path at Package resolution time
func clangLibPath() -> String {
    // LD_LIBRARY_PATH: /Applications/Xcode.app/Contents/Developer/../SharedFrameworks/
    guard let ldLibraryPath = ProcessInfo().environment["LD_LIBRARY_PATH"],
          !ldLibraryPath.isEmpty else {
        fatalError("LD_LIBRARY_PATH is not set: \(ProcessInfo.processInfo.environment.map { "\($0): \($1)" }.joined(separator: "; "))")
    }
    let developerPath = "/" + ldLibraryPath.split(separator: "/").dropLast(2).joined(separator: "/")
    let clangPath = developerPath + "/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/"

    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: clangPath) else {
        fatalError("Failed to get contents of \(clangPath)")
    }
    // get the first clang version number with format 16.0.0 from the contents
    let versionRegex = try? NSRegularExpression(pattern: "[0-9]+\\.[0-9]+\\.[0-9]+")
    guard let clangVersion = contents.first(where: {
        versionRegex?.firstMatch(in: $0, range: NSRange(location: 0, length: $0.utf16.count)) != nil
    }) else {
        fatalError("Failed to get clang version from \(contents)")
    }
    let clangLibPath = clangPath + clangVersion + "/lib/darwin"

    // /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/16.0.0/lib/darwin
    return clangLibPath
}
