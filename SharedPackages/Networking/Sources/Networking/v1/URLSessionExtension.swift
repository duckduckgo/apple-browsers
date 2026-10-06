//
//  URLSessionExtension.swift
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

extension URLSession {

    private static var defaultCallbackQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "APIRequest default callback queue"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private static let defaultCallback = URLSession(configuration: .default, delegate: nil, delegateQueue: defaultCallbackQueue)
    private static let defaultCallbackEphemeral = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: defaultCallbackQueue)

    private static let mainThreadCallback = URLSession(configuration: .default, delegate: nil, delegateQueue: OperationQueue.main)
    private static let mainThreadCallbackEphemeral = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: OperationQueue.main)

    public static func session(useMainThreadCallbackQueue: Bool = false, ephemeral: Bool = true) -> URLSession {
        if useMainThreadCallbackQueue {
            return ephemeral ? mainThreadCallbackEphemeral : mainThreadCallback
        } else {
            return ephemeral ? defaultCallbackEphemeral : defaultCallback
        }
    }

}
