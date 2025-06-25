//
//  Action.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public enum ActionType: String, Codable, Sendable {
    case extract
    case navigate
    case fillForm
    case click
    case expectation
    case emailConfirmation
    case getCaptchaInfo
    case solveCaptcha
}

public enum DataSource: String, Codable, Sendable {
    case userProfile
    case extractedProfile
}

public protocol Action: Codable, Sendable {
    var id: String { get }
    var actionType: ActionType { get }
    var needsEmail: Bool { get }
    var dataSource: DataSource { get }

    /// Certain brokers force a page reload with a random time interval when the user lands on the search result
    /// page. The first time the action runs the C-S-S context is lost as the page is reloading and C-S-S fails
    /// to respond to the native message.
    ///
    /// This decides whether a given action can time out.
    ///
    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1210079565270206?focus=true
    func canTimeOut(while stepType: StepType?) -> Bool
}

extension Action {
    public var needsEmail: Bool { false }
    public var dataSource: DataSource { .userProfile }

    public func canTimeOut(while stepType: StepType?) -> Bool {
        true
    }
}
