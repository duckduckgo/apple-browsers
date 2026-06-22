//
//  AutocompleteRequestRunner.swift
//  DuckDuckGo
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

import Foundation

/// Owns a single in-flight autocomplete network request and cancels the prior one when a new
/// request starts. One instance per suggestions surface — sharing a single task across surfaces
/// makes them cancel each other's requests.
final class AutocompleteRequestRunner {

    private var task: URLSessionDataTask?

    func run(_ request: URLRequest, completion: @escaping (Data?, Error?) -> Void) {
        task?.cancel()
        task = URLSession.shared.dataTask(with: request) { data, _, error in
            completion(data, error)
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
