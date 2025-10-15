//
//  MockAutofillUsageProvider.swift
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

@testable import BrowserServicesKit
import Foundation

public final class MockAutofillUsageProvider: AutofillUsageProvider {
    public var formattedFillDate: String?
    public var fillDate: Date?
    public var lastActiveDate: Date?
    public var formattedLastActiveDate: String?
    public var isOnboarded: Bool
    public var searchDauDate: Date?

    public init(
        formattedFillDate: String? = nil,
        fillDate: Date? = nil,
        lastActiveDate: Date? = nil,
        formattedLastActiveDate: String? = nil,
        isOnboarded: Bool = true,
        searchDauDate: Date? = nil
    ) {
        self.formattedFillDate = formattedFillDate
        self.fillDate = fillDate
        self.lastActiveDate = lastActiveDate
        self.formattedLastActiveDate = formattedLastActiveDate
        self.isOnboarded = isOnboarded
        self.searchDauDate = searchDauDate
    }
}
