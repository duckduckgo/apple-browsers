//
//  Update+Sparkle.swift
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

import AppUpdaterShared
import Foundation
import Sparkle

extension Update {
    convenience init(appcastItem: SUAppcastItem, isInstalled: Bool, dateFormatterProvider: @autoclosure @escaping () -> DateFormatter = Update.releaseDateFormatter()) {
        let isCritical = appcastItem.isCriticalUpdate
        let version = appcastItem.displayVersionString
        let build = appcastItem.versionString
        let date = appcastItem.date ?? Date()
        let (releaseNotes, releaseNotesSubscription) = ReleaseNotesParser.parseReleaseNotes(from: appcastItem.itemDescription)

        self.init(isInstalled: isInstalled,
                  type: isCritical ? .critical : .regular,
                  version: version,
                  build: build,
                  date: date,
                  releaseNotes: releaseNotes,
                  releaseNotesSubscription: releaseNotesSubscription,
                  dateFormatterProvider: dateFormatterProvider())
    }

}
