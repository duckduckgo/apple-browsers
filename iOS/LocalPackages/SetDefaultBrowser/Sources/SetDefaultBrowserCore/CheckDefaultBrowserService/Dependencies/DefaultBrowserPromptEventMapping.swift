//
//  DefaultBrowserPromptEventMapping.swift
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

public protocol DefaultBrowserPromptEventMapping<Event> {
    associatedtype Event
    func fire(_ event: Event, error: Error?, parameters: [String: String]?, onComplete: @escaping (Error?) -> Void)
}

public extension DefaultBrowserPromptEventMapping {

    func fire(_ event: Event) {
        fire(event, error: nil, parameters: nil, onComplete: { _ in })
    }

    func fire(_ event: Event, error: Error) {
        fire(event, error: error, parameters: nil, onComplete: { _ in })
    }

}
