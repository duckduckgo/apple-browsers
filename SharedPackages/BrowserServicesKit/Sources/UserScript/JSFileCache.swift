//
//  JSFileCache.swift
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

enum JSFileCache {

    private static let lock = NSLock()
    private static var storage = [String: String]()

    static func content(forFile file: String, in bundle: Bundle) throws -> String {
        let cacheKey = bundle.bundlePath + "/" + file

        lock.lock()
        let cached = storage[cacheKey]
        lock.unlock()

        if let cached { return cached }

        guard let path = bundle.path(forResource: file, ofType: "js") else {
            throw UserScriptError.failedToLoadJS(jsFile: file, error: CocoaError(.fileReadNoSuchFile))
        }

        do {
            let content = try String(contentsOfFile: path)
            lock.lock()
            storage[cacheKey] = content
            lock.unlock()
            return content
        } catch {
            throw UserScriptError.failedToLoadJS(jsFile: file, error: error)
        }
    }
}
