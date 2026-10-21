//
//  WKPageLoadTiming.swift
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

import Foundation

/// Class that reproduces WebKit's private _WKPageLoadTiming interface
/// and provides comprehensive page load performance milestones
public final class WKPageLoadTiming {

    // MARK: - Private Constants

    private enum Keys {
        static let navigationStart = "navigationStart"
        static let firstVisualLayout = "firstVisualLayout"
        static let firstMeaningfulPaint = "firstMeaningfulPaint"
        static let documentFinishedLoading = "documentFinishedLoading"
        static let allSubresourcesFinishedLoading = "allSubresourcesFinishedLoading"
    }

    // MARK: - Public Properties

    public let navigationStart: Date?
    public let firstVisualLayout: Date?
    public let firstMeaningfulPaint: Date?
    public let documentFinishedLoading: Date?
    public let allSubresourcesFinishedLoading: Date?

    // MARK: - Initialization

    public init(_ timing: NSObject) {
        // Use KVC to safely extract properties from WebKit's private _WKPageLoadTiming object
        self.navigationStart = timing.value(forKey: Keys.navigationStart) as? Date
        self.firstVisualLayout = timing.value(forKey: Keys.firstVisualLayout) as? Date
        self.firstMeaningfulPaint = timing.value(forKey: Keys.firstMeaningfulPaint) as? Date
        self.documentFinishedLoading = timing.value(forKey: Keys.documentFinishedLoading) as? Date
        self.allSubresourcesFinishedLoading = timing.value(forKey: Keys.allSubresourcesFinishedLoading) as? Date
    }
}
