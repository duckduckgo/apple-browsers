//
//  Untitled.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import TrackerRadarKit

extension NSAlert {

    static func storageAccessAlert(currentDomain: String,
                                   requestingDomain: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = UserText.storageAccessPromptHeader
        alert.alertStyle = .warning
        alert.icon = .privacyQuestion
        alert.addButton(withTitle: UserText.storageAccessPromptAllow)
        alert.addButton(withTitle: UserText.storageAccessPromptDontAllow)
        alert.buttons.first?.keyEquivalent = "\r"

        let containerWidth: CGFloat = 300
        let marginX: CGFloat = 10
        let contentWidth: CGFloat = containerWidth - marginX * 2
        let verticalSpacing: CGFloat = 10
        let topPadding: CGFloat = 0
        let bottomPadding: CGFloat = 10

        // Mixed-style label: bold only the domains
        let domainLabel: NSTextField = {
            let label = NSTextField(labelWithString: "")
            let text = UserText.storageAccessPromptLabel1(currentDomain: currentDomain,
                                                          requestingDomain: requestingDomain)

            let attributed = NSMutableAttributedString(string: text,
                attributes: [.font: NSFont.systemFont(ofSize: 12)])

            // Bold domains
            let reqRange = (text as NSString).range(of: requestingDomain)
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: reqRange)
            let currRange = (text as NSString).range(of: currentDomain)
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: currRange)

            // Center-align all lines via paragraph style for attributed string
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            attributed.addAttribute(.paragraphStyle,
                                    value: paragraphStyle,
                                    range: NSRange(location: 0, length: attributed.length))
            label.attributedStringValue = attributed
            label.usesSingleLineMode = false
            label.cell?.isScrollable = false
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = false
            label.lineBreakMode = .byWordWrapping
            label.alignment = .center
            return label
        }()

        // Other labels
        let labels = [
            domainLabel,
            makeLabel(UserText.storageAccessPromptLabel2, bold: false, size: 12),
            makeLabel(UserText.storageAccessPromptLabel3, bold: false, size: 12)
        ]

        // Size each to wrap at our target width
        for label in labels {
            let boundingSize = CGSize(width: contentWidth,
                                      height: CGFloat.greatestFiniteMagnitude)
            let boundingRect = label.attributedStringValue.boundingRect(
                with: boundingSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            label.frame = CGRect(origin: .zero,
                                 size: CGSize(width: contentWidth,
                                              height: ceil(boundingRect.height)))
        }

        // Compute total height
        var totalHeight: CGFloat = topPadding
        for (i, label) in labels.enumerated() {
            totalHeight += label.frame.height
            if i < labels.count - 1 {
                totalHeight += verticalSpacing
            }
        }
        totalHeight += bottomPadding

        // Make container & position
        let container = NSView(frame: CGRect(x: 0, y: 0,
                                             width: containerWidth,
                                             height: totalHeight))

        // Prevent NSAlert from stretching accessory view to its default width
        container.autoresizingMask = []
        var y = totalHeight - topPadding
        for (labelIndex, label) in labels.enumerated() {
            y -= label.frame.height
            label.frame.origin = CGPoint(x: marginX, y: y)
            container.addSubview(label)
            if labelIndex < labels.count - 1 {
                y -= verticalSpacing
            }
        }

        alert.accessoryView = container
        return alert
    }

    static func makeLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        // Create a "label" style text field
        let label = NSTextField(labelWithString: text)
        label.font = bold
            ? .boldSystemFont(ofSize: size)
            : .systemFont(ofSize: size)

        // **Enable wrapping & multi-line:**
        // Turn off the "single-line" optimization:
        label.usesSingleLineMode = false
        // Prevent horizontal scrolling so wrapping takes effect
        label.cell?.isScrollable = false
        // Make the cell actually wrap
        label.cell?.wraps = true
        // Don't ever truncate
        label.cell?.truncatesLastVisibleLine = false
        // Use word wrapping, not character-by-character
        label.lineBreakMode = .byWordWrapping
        // Center-align the text in each label
        label.alignment = .center

        return label
    }

    static func storageAccessAlertForQuirkDomains(requestingDomain: String, currentDomain: String, quirkDomains: [String]) -> NSAlert {
        let alert = NSAlert()
        let entity = entity(from: requestingDomain)
        alert.messageText = UserText.storageAccessQuirkDomainsPromptHeader(entity: entity)
        alert.informativeText = UserText.storageAccessQuirkDomainsPromptBody(entity: entity, quirkDomains: quirkDomains.joined(separator: ", "))
        alert.alertStyle = .warning
        alert.icon = .privacyQuestion
        alert.addButton(withTitle: UserText.permissionPopupAllowButton)
        alert.addButton(withTitle: UserText.permissionPopoverDenyButton)

        // Force the alert to be wider
        let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 1))
        alert.accessoryView = spacer
        return alert
    }

    fileprivate static func entity(from requestingDomain: String, tds: TrackerData = ContentBlocking.shared.trackerDataManager.trackerData) -> String {
        if let entity = tds.findEntity(forHost: requestingDomain),
           let entityName = entity.displayName {
            return entityName
        } else {
            return "\"\(requestingDomain)\""
        }
    }

}
