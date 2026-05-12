//
//  CompleteDownloadRowViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Core
import EventKit
import Foundation
import ICSParser

class CompleteDownloadRowViewModel: DownloadsListRowViewModel {
    var fileURL: URL
    var fileSize: String

    private let featureFlagger: FeatureFlagger

    init(fileURL: URL, featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.fileURL = fileURL
        self.fileSize = DownloadsListRowViewModel.byteCountFormatter.string(fromByteCount: Int64(fileURL.fileSize))
        self.featureFlagger = featureFlagger
        super.init(filename: fileURL.filename)
    }

    /// Returns the editor-ready event when the file should open in `EKEventEditViewController`;
    /// nil when the feature is off, the OS is < 17, the file isn't `.ics`, or it's not a
    /// single-VEVENT calendar.
    func preparePreviewEvent() -> PreparedCalendarEvent? {
        guard #available(iOS 17, *),
              featureFlagger.isFeatureOn(.icsCalendarLinks),
              fileURL.pathExtension.lowercased() == "ics",
              let data = try? Data(contentsOf: fileURL),
              let events = try? ICSParser.parse(data: data),
              events.count == 1 else {
            return nil
        }
        let store = EKEventStore()
        let event = CalendarEventPreviewHelper.makeEKEvent(from: events[0], in: store)
        return PreparedCalendarEvent(event: event, store: store)
    }
}
