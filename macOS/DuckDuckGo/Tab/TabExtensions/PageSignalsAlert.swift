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
        let alert = buildAlert(signals: signals)
        alert.runModal()
    }
}

// MARK: - Private

private extension PageSignalsAlert {

    func buildAlert(signals: PageSignals?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Page Signals"

        guard let signals else {
            alert.informativeText = "No signals collected for this tab. Is the pageSignals feature flag enabled?"
            return alert
        }

        alert.informativeText = signals.host ?? "Unknown host"
        alert.accessoryView = buildAccessoryView(signals: signals)
        alert.addButton(withTitle: "Dismiss")

        return alert
    }

    func buildAccessoryView(signals: PageSignals) -> NSView {
        let payload = signals.description
        let label = NSTextField(labelWithString: payload)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.sizeToFit()

        return label
    }
}

private extension PageSignals {

    var description: String {
        let columnWidth = 18
        let header = "Blocked loads".padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            + "\(blockedLoads)"

        let failureLines = resourceFailures
            .sorted { $0.key < $1.key }
            .map { domain, errors in
                let messages = errors.map { "\($0)" }.sorted().joined(separator: ", ")
                return "  \(domain): \(messages)"
            }

        let failureSection = failureLines.isEmpty ? ["  None"] : failureLines

        return ([header, "", "Resource failures"] + failureSection)
            .joined(separator: "\n")
    }

}
