//
//  MockDefaultBrowsePromptUserActivityStore.swift
//  DuckDuckGo
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

import SetDefaultBrowserCore

public final class MockDefaultBrowsePromptUserActivityStore: DefaultBrowsePromptUserActivityStorage {
    public private(set) var didCallSaveActivity: Bool = false
    public private(set) var capturedSaveActivity: DefaultBrowserPromptUserActivity?
    public private(set) var didCallDeleteActivity: Bool = false

    public var activityToReturn: DefaultBrowserPromptUserActivity = .init()

    public init() {}

    public func save(_ activity: DefaultBrowserPromptUserActivity) {
        didCallSaveActivity = true
        capturedSaveActivity = activity
    }
    
    public func deleteActivity() {
        didCallDeleteActivity = true
    }
    
    public func currentActivity() -> DefaultBrowserPromptUserActivity {
        activityToReturn
    }
}
