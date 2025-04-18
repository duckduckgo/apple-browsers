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

    static func storageAccessAlert(currentDomain: String, requestingDomain: String) -> NSAlert {
        let alert = NSAlert()
        let entity = entity(from: requestingDomain)
        alert.messageText = UserText.storageAccessPromptHeader(currentDomain: "\"\(currentDomain)\"",
                                                               requestingDomain: "\"\(requestingDomain)\"")
        alert.informativeText = UserText.storageAccessPromptBody(entity: entity, domain: "\"\(currentDomain)\"")
        alert.alertStyle = .warning
        alert.icon = .alertColor16
        alert.addButton(withTitle: UserText.permissionPopupAllowButton)
        alert.addButton(withTitle: UserText.permissionPopoverDenyButton)

        // Force the alert to be wider
        let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 1))
        alert.accessoryView = spacer
        return alert
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
