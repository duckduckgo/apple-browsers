//
//  NewTabPageRemoteMessageImpressionReporter.swift
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

import RemoteMessaging

/// A macOS NTP impression is one supported message shown on a selected, attached regular NTP tab.
/// Repeated display/update callbacks for the same tab and message are one continuous showing; leaving
/// the NTP or selecting another tab ends it, so returning to the message is counted again.
final class NewTabPageRemoteMessageImpressionReporter {
    private struct Showing: Equatable {
        let tabID: String
        let messageID: String
    }

    private(set) var visibleTabID: String?
    private var reportedShowing: Showing?
    private let reportVisibleMessage: (String) -> Void

    init(reportVisibleMessage: @escaping (String) -> Void) {
        self.reportVisibleMessage = reportVisibleMessage
    }

    func updateVisibleTab(_ tabID: String?, message: RemoteMessageModel?) {
        visibleTabID = tabID
        updateMessage(message)
    }

    func updateMessage(_ message: RemoteMessageModel?) {
        guard let visibleTabID,
              let message,
              message.surfaces.contains(.newTabPage),
              message.content?.isSupported == true else {
            reportedShowing = nil
            return
        }

        let showing = Showing(tabID: visibleTabID, messageID: message.id)
        guard showing != reportedShowing else { return }
        reportedShowing = showing
        reportVisibleMessage(message.id)
    }
}
