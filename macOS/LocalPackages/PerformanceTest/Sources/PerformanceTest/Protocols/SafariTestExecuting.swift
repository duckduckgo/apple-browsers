//
//  SafariTestExecuting.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@MainActor
public protocol SafariTestExecuting {
    var url: URL { get }
    var iterations: Int { get }
    var progressHandler: ((Int, Int, String) -> Void)? { get set }
    var isCancelled: () -> Bool { get set }

    func runTest() async throws -> String
    func cleanup()
}
