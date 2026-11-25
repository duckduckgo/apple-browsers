//
//  OtherDistributionInstalledPixelReporterTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Foundation
@_spi(Testing) import PixelKit
import Testing

@testable import DuckDuckGo_Privacy_Browser

@Suite("Other distribution installed pixel")
struct OtherDistributionInstalledPixelReporterTests {

    @available(iOS 16, macOS 13, *)
    @Test("Each build looks for every variant of the other build's bundle ID", .timeLimit(.minutes(1)), arguments: [
        (true, "com.duckduckgo.macos.browser"),
        (false, "com.duckduckgo.mobile.ios"),
    ])
    func looksUpOtherBundleIdentifiers(isAppStoreBuild: Bool, otherBundleIdentifier: String) {
        var requestedBundleIdentifiers: [String] = []
        let reporter = OtherDistributionInstalledPixelReporter(isAppStoreBuild: isAppStoreBuild,
                                                               applicationURLs: { requestedBundleIdentifiers.append($0); return [] },
                                                               pixelFiring: PixelKitMock())

        reporter.fireDailyPixel()

        #expect(requestedBundleIdentifiers == [
            otherBundleIdentifier,
            otherBundleIdentifier + ".debug",
            otherBundleIdentifier + ".review",
            otherBundleIdentifier + ".alpha",
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports installed when only an internal variant is in /Applications", .timeLimit(.minutes(1)))
    func reportsInstalledForInternalVariant() {
        let pixelKit = PixelKitMock()
        let reporter = OtherDistributionInstalledPixelReporter(
            isAppStoreBuild: false,
            applicationURLs: { $0 == "com.duckduckgo.mobile.ios.debug" ? [URL(fileURLWithPath: "/Applications/DuckDuckGo.app")] : [] },
            pixelFiring: pixelKit
        )

        reporter.fireDailyPixel()

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: OtherDistributionInstalledPixel.daily(installed: true), frequency: .daily)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports installed only for copies in /Applications", .timeLimit(.minutes(1)), arguments: [
        ([String](), false),
        (["/Users/someone/Downloads/DuckDuckGo.app"], false),
        (["/Applications/Utilities/DuckDuckGo.app"], false),
        (["/Users/someone/Applications/DuckDuckGo.app"], false),
        (["/Applications/DuckDuckGo.app"], true),
        (["/Users/someone/Downloads/DuckDuckGo.app", "/Applications/DuckDuckGo 2.app/"], true),
    ])
    func reportsInstalledForApplicationsFolderOnly(paths: [String], expectedInstalled: Bool) {
        let pixelKit = PixelKitMock()
        let reporter = OtherDistributionInstalledPixelReporter(isAppStoreBuild: false,
                                                               applicationURLs: { _ in paths.map { URL(fileURLWithPath: $0) } },
                                                               pixelFiring: pixelKit)

        reporter.fireDailyPixel()

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: OtherDistributionInstalledPixel.daily(installed: expectedInstalled), frequency: .daily)
        ])
        #expect(pixelKit.actualFireCalls.first?.pixel.name == "other_distribution_installed_macos")
        #expect(pixelKit.actualFireCalls.first?.pixel.parameters == ["installed": String(expectedInstalled)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Bundle IDs match the xcconfig files", .timeLimit(.minutes(1)), arguments: [
        ("DeveloperID.xcconfig", OtherDistributionInstalledPixelReporter.dmgBundleIdentifier),
        ("AppStore.xcconfig", OtherDistributionInstalledPixelReporter.appStoreBundleIdentifier),
    ])
    func bundleIdentifiersMatchXcconfig(fileName: String, bundleIdentifier: String) throws {
        let xcconfig = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Configuration").appendingPathComponent(fileName)
        let lines = try String(contentsOf: xcconfig, encoding: .utf8).components(separatedBy: .newlines)

        #expect(lines.contains("MAIN_BUNDLE_IDENTIFIER_PREFIX = \(bundleIdentifier)"))
        let suffixes = lines
            .filter { $0.hasPrefix("MAIN_BUNDLE_IDENTIFIER[") }
            .map { $0.components(separatedBy: "$(MAIN_BUNDLE_IDENTIFIER_PREFIX)").last ?? "" }
        #expect(Set(suffixes) == Set(OtherDistributionInstalledPixelReporter.bundleIdentifierSuffixes))
    }
}
