//
//  NSAlert+Tab.swift
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

import AppKit
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

        let domainLabel = makeDomainLabel(currentDomain: currentDomain, requestingDomain: requestingDomain)

        // Other labels
        let labels = [
            domainLabel,
            makeLabel(UserText.storageAccessPromptLabel2(entity: entity(from: requestingDomain)), bold: false, size: 12),
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
        let label = NSTextField(labelWithString: text)
        label.font = bold
            ? .boldSystemFont(ofSize: size)
            : .systemFont(ofSize: size)

        label.usesSingleLineMode = false
        label.cell?.isScrollable = false
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = false
        label.lineBreakMode = .byWordWrapping
        label.alignment = .center
        label.textColor = NSColor.labelColor

        return label
    }

    /// Creates the domain label with bolded domains and centered alignment.
    private static func makeDomainLabel(currentDomain: String, requestingDomain: String, fontSize: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let text = UserText.storageAccessPromptLabel1(currentDomain: currentDomain,
                                                      requestingDomain: requestingDomain)
        let attributed = NSMutableAttributedString(string: text,
                                                   attributes: [
                                                    .font: NSFont.systemFont(ofSize: fontSize),
                                                    .foregroundColor: NSColor.labelColor
                                                   ])
        let reqRange = (text as NSString).range(of: requestingDomain)
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: reqRange)
        let currRange = (text as NSString).range(of: currentDomain)
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: currRange)
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
    }

    static func storageAccessAlertForQuirkDomains(requestingDomain: String, currentDomain: String, quirkDomains: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = UserText.storageAccessPromptQuirkDomainsHeader
        alert.alertStyle = .warning
        alert.icon = .privacyQuestion
        alert.addButton(withTitle: UserText.storageAccessPromptAllow)
        alert.addButton(withTitle: UserText.storageAccessPromptDontAllow)

        // Make Allow the default button
        alert.buttons.first?.keyEquivalent = "\r"

        // Build labels
        let introLabel = makeIntroLabel(requestingDomain: requestingDomain, fontSize: 12)
        let domainListLabels = quirkDomains.map { makeLabel($0, bold: true, size: 12) }
        let selectionLabel = makeLabel(UserText.storageAccessPromptLabel2(entity: entity(from: requestingDomain)), bold: false, size: 12)
        let protectionLabel = makeLabel(UserText.storageAccessPromptLabel3, bold: false, size: 12)
        let labels = [introLabel] + domainListLabels + [selectionLabel, protectionLabel]

        // Layout constants
        let containerWidth: CGFloat = 320
        let marginX: CGFloat = 8
        let contentWidth: CGFloat = containerWidth - marginX * 2
        let verticalSpacing: CGFloat = 10
        let topPadding: CGFloat = 0
        let bottomPadding: CGFloat = 10

        // Size each label
        for label in labels {
            let boundingSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            let boundingRect = label.attributedStringValue.boundingRect(
                with: boundingSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            label.frame = CGRect(origin: .zero,
                                 size: CGSize(width: contentWidth,
                                              height: ceil(boundingRect.height)))
        }

        // Remove spacing between intro and domain list, and between domain labels
        let domainCount = domainListLabels.count
        let lastDomainIndex = domainCount
        let selectionLabelIndex = domainCount + 1

        // Compute total height
        var totalHeight: CGFloat = topPadding
        for (i, label) in labels.enumerated() {
            totalHeight += label.frame.height
            if i < labels.count - 1 && (i == lastDomainIndex || i == selectionLabelIndex) {
                totalHeight += verticalSpacing
            }
        }
        totalHeight += bottomPadding

        // Create container and position labels
        let container = NSView(frame: CGRect(x: 0, y: 0, width: containerWidth, height: totalHeight))
        container.autoresizingMask = []
        var yPosition = totalHeight - topPadding
        for (i, label) in labels.enumerated() {
            yPosition -= label.frame.height
            label.frame.origin = CGPoint(x: marginX, y: yPosition)
            container.addSubview(label)
            if i < labels.count - 1 && (i == lastDomainIndex || i == selectionLabelIndex) {
                yPosition -= verticalSpacing
            }
        }

        alert.accessoryView = container
        return alert
    }

    private static func entity(from requestingDomain: String, tds: TrackerData = Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.trackerData) -> String {
        if let entity = tds.findEntity(forHost: requestingDomain),
           let entityName = entity.displayName {
            return entityName
        } else {
            return "\(requestingDomain)"
        }
    }

    /// Creates an intro label with the requesting domain bolded and centered alignment.
    private static func makeIntroLabel(requestingDomain: String, fontSize: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let text = UserText.storageAccessPromptQuirkDomainsLabel1(requestingDomain: requestingDomain)
        let attributed = NSMutableAttributedString(string: text,
                                                   attributes: [
                                                    .font: NSFont.systemFont(ofSize: fontSize),
                                                    .foregroundColor: NSColor.labelColor
                                                   ])
        let reqRange = (text as NSString).range(of: requestingDomain)
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: reqRange)
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
    }

}
