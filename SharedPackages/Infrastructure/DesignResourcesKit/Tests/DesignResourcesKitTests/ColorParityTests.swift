//
//  ColorParityTests.swift
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

import XCTest
import SwiftUI
@testable import DesignResourcesKit

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Snapshot guardrail for the colour system.
///
/// Resolves every colour reachable through the public API — every `DesignSystemColor`,
/// `SingleUseColor` and `BaseColor` — in every palette, in both light and dark, to an
/// `#RRGGBBAA` string, and diffs the result against a committed per-platform baseline.
///
/// Run with the environment variable `RECORD=1` to (re)write the baseline instead of asserting.
final class ColorParityTests: XCTestCase {

    func testColorParity() throws {
        try compareOrRecord(Self.resolvedColors(), platform: Self.platformName)
    }

    // MARK: - Baseline comparison

    private func compareOrRecord(_ colors: [String: String], platform: String) throws {
        let baselineURL = Self.baselineDirectory.appendingPathComponent("\(platform)-colors.json")

        if ProcessInfo.processInfo.environment["RECORD"] == "1" {
            try FileManager.default.createDirectory(at: Self.baselineDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: colors, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: baselineURL)
            print("📸 Recorded \(colors.count) colours to \(baselineURL.path)")
            return
        }

        guard let data = try? Data(contentsOf: baselineURL),
              let baseline = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            XCTFail("No baseline at \(baselineURL.path). Run the test with RECORD=1 to create it.")
            return
        }

        let current = Set(colors.keys)
        let recorded = Set(baseline.keys)
        let missing = recorded.subtracting(current).sorted()
        let unexpected = current.subtracting(recorded).sorted()
        let changed = current.intersection(recorded).filter { colors[$0] != baseline[$0] }.sorted()

        guard missing.isEmpty, unexpected.isEmpty, changed.isEmpty else {
            XCTFail(Self.diffReport(platform: platform,
                                    baseline: baseline,
                                    colors: colors,
                                    missing: missing,
                                    unexpected: unexpected,
                                    changed: changed))
            return
        }
    }

    private static func diffReport(platform: String,
                                   baseline: [String: String],
                                   colors: [String: String],
                                   missing: [String],
                                   unexpected: [String],
                                   changed: [String]) -> String {
        let cap = 25
        func list(_ label: String, _ keys: [String], _ render: (String) -> String) -> String? {
            guard !keys.isEmpty else { return nil }
            let shown = keys.prefix(cap).map(render).joined(separator: "\n  ")
            let more = keys.count > cap ? "\n  … and \(keys.count - cap) more" : ""
            return "\(label) (\(keys.count)):\n  \(shown)\(more)"
        }

        let sections = [
            list("Changed", changed) { "\($0): \(baseline[$0] ?? "?") → \(colors[$0] ?? "?")" },
            list("Missing from output", missing) { "\($0): \(baseline[$0] ?? "?")" },
            list("Unexpected new keys", unexpected) { "\($0): \(colors[$0] ?? "?")" }
        ].compactMap { $0 }

        return """
        Colour parity baseline mismatch for \(platform).
        \(sections.joined(separator: "\n"))

        If this change is intended, review the rendered colour diff with the maintainer, then re-record with RECORD=1.
        """
    }

    // MARK: - Helpers

    private static var baselineDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Baselines")
    }

    private static var platformName: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    /// Formats resolved RGBA components (0...1) as `#RRGGBBAA`
    fileprivate static func hexString(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> String {
        func channel(_ value: CGFloat) -> Int { max(0, min(255, Int((value * 255).rounded()))) }
        return String(format: "#%02X%02X%02X%02X", channel(red), channel(green), channel(blue), channel(alpha))
    }
}

#if os(iOS)

private extension ColorParityTests {

    static func resolvedColors() -> [String: String] {
        var colors: [String: String] = [:]

        let palettes: [(name: String, palette: ColorPalette)] = [
            ("legacy", .legacy),
            ("default", .default)
        ]

        for (name, palette) in palettes {
            for color in DesignSystemColor.allCases {
                record(&colors, "designSystem.\(key(color)).\(name)", UIColor(designSystemColor: color, palette: palette))
            }
            for color in SingleUseColor.allCases {
                record(&colors, "singleUse.\(key(color)).\(name)", UIColor(singleUseColor: color, palette: palette))
            }
            for color in BaseColor.allCases {
                record(&colors, "baseColor.\(key(color)).\(name)", UIColor(baseColor: color, palette: palette))
            }
        }

        return colors
    }

    static func record(_ colors: inout [String: String], _ key: String, _ color: UIColor) {
        colors["\(key).light"] = resolved(color, dark: false)
        colors["\(key).dark"] = resolved(color, dark: true)
    }

    static func resolved(_ color: UIColor, dark: Bool) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return hexString(red: r, green: g, blue: b, alpha: a)
    }

    static func key(_ color: DesignSystemColor) -> String { "\(color)" }
    static func key(_ color: BaseColor) -> String { "\(color)" }
    static func key(_ color: SingleUseColor) -> String {
        if case let .rebranding(rebranding) = color { return "rebranding.\(rebranding)" }
        return "\(color)"
    }
}

#endif

#if os(macOS)

private extension ColorParityTests {

    static var scenarios: [(name: String, palette: ColorPalette)] {
        [
            ("default", .default),
            ("legacy", .legacy),
            ("coolGray", .coolGray),
            ("desert", .desert),
            ("green", .green),
            ("orange", .orange),
            ("rose", .rose),
            ("slateBlue", .slateBlue),
            ("violet", .violet)
        ]
    }

    static func resolvedColors() -> [String: String] {
        var colors: [String: String] = [:]

        for scenario in scenarios {
            for color in SharedDesignSystemColor.allCases {
                record(&colors, "designSystem.\(color).\(scenario.name)", NSColor(designSystemColor: color, palette: scenario.palette))
            }
            for color in SharedSingleUseColor.allCases {
                record(&colors, "singleUse.\(color).\(scenario.name)", NSColor(singleUseColor: color, palette: scenario.palette))
            }
            for color in BaseColor.allCases {
                record(&colors, "baseColor.\(color).\(scenario.name)", NSColor(baseColor: color, palette: scenario.palette))
            }
        }

        return colors
    }

    static func record(_ colors: inout [String: String], _ key: String, _ color: NSColor) {
        colors["\(key).light"] = resolved(color, dark: false)
        colors["\(key).dark"] = resolved(color, dark: true)
    }

    static func resolved(_ color: NSColor, dark: Bool) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(.sRGB) ?? color
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        return hexString(red: r, green: g, blue: b, alpha: a)
    }
}

#endif
