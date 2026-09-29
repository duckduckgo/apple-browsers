//
//  PageSignalsAlert.swift
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

import AppKit
import DDGNavigation

/// Debug alert that displays a tab's page signals, and copies them on request.
@MainActor
struct PageSignalsAlert {
    let signals: PageSignals?

    func runModal() {
        let alert = NSAlert()
        alert.messageText = "Page Signals"

        guard let signals else {
            alert.informativeText = "No signals collected for this tab. Is the pageSignals feature flag enabled?"
            alert.runModal()
            return
        }

        let report = Self.report(for: signals)
        let reportLabel = NSTextField(labelWithString: report)
        reportLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        reportLabel.isSelectable = true
        reportLabel.sizeToFit()

        alert.informativeText = signals.pageHost ?? "Unknown host"
        alert.accessoryView = reportLabel
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Close")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        NSPasteboard.general.copy(report)
    }

    private static func report(for signals: PageSignals) -> String {
        func row(_ title: String, _ value: String) -> String {
            title.padding(toLength: 18, withPad: " ", startingAt: 0) + value
        }

        let blankPage = signals.isBlankPage.map { $0 ? "Yes" : "No" } ?? "Unknown"
        let failures = signals.resourceFailures.isEmpty
            ? ["  None"]
            : signals.resourceFailures.sorted { $0.key < $1.key }.map { domain, errors in
                "  \(domain): " + errors.map { "\($0)" }.sorted().joined(separator: ", ")
            }

        return ([
            row("Blank page", blankPage),
            row("Blocked loads", "\(signals.blockedLoads)"),
            row("Blocked cookies", "\(signals.blockedCookies)"),
            row("Modified headers", "\(signals.modifiedHeaders)"),
            "",
            "Resource failures",
        ] + failures).joined(separator: "\n")
    }
}
