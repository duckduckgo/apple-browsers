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
        alert.messageText = "Allow sharing of cookies and website data?"
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Allow")

        let contentWidth: CGFloat = 360 - 20  // account for 10-point margins
        let verticalSpacing: CGFloat = 8

        // 1) Build labels
        let labels = [
          makeLabel("This site:", bold: false, size: 13),
          makeLabel(currentDomain, bold: true, size: 13),
          makeLabel("Has requested to use cookies and other website data (such as login information) on their other site:", bold: false, size: 13),
          makeLabel(requestingDomain, bold: true, size: 13),
          makeLabel("Declining may result in the site not working properly, but will prevent tracking across websites. DuckDuckGo's Web Tracking Protections will still apply either way.", bold: false, size: 12)
        ]

        // 2) Size each to wrap at our target width
        for label in labels {
            // compute height for wrapping text at our fixed width
            let boundingSize = CGSize(width: contentWidth,
                                      height: CGFloat.greatestFiniteMagnitude)
            let boundingRect = label.attributedStringValue.boundingRect(
                with: boundingSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            // set the field's frame to the fixed width and calculated height
            label.frame = CGRect(origin: .zero,
                                 size: CGSize(width: contentWidth,
                                              height: ceil(boundingRect.height)))
        }

        // 3) Compute total height
        var totalHeight: CGFloat = 10  // top padding
        for (i, label) in labels.enumerated() {
            totalHeight += label.frame.height
            if i < labels.count - 1 {
                totalHeight += verticalSpacing
            }
        }
        totalHeight += 10  // bottom padding

        // 4) Make container & position
        let container = NSView(frame: CGRect(x: 0, y: 0,
                                             width: 360,
                                             height: totalHeight))
        // Prevent NSAlert from stretching accessory view to its default width
        container.autoresizingMask = []
        var y = totalHeight - 10
        for label in labels {
            y -= label.frame.height
            label.frame.origin = CGPoint(x: 10, y: y)
            container.addSubview(label)
            y -= verticalSpacing
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

        return label
    }

    static func storageAccessAlertForQuirkDomains(requestingDomain: String, currentDomain: String, quirkDomains: [String]) -> NSAlert {
        let alert = NSAlert()
        let entity = entity(from: requestingDomain)
        alert.messageText = UserText.storageAccessQuirkDomainsPromptHeader(entity: entity)
        alert.informativeText = UserText.storageAccessQuirkDomainsPromptBody(entity: entity, quirkDomains: quirkDomains.joined(separator: ", "))
        alert.alertStyle = .warning
        alert.icon = .alertColor16
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
