//
//  StubScriptletValidator.swift
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
import os.log

public final class StubScriptletValidator: ScriptletValidating {

    public init() {}

    public func validate(_ fetched: [FetchedScriptlet]) throws -> [Scriptlet] {
        Logger.webExtensions.debug("[Scriptlets] ✓ Stub validator: passing through \(fetched.count) scriptlet(s) without validation")
        return fetched.map { item in
            Scriptlet(name: item.descriptor.name, content: item.data)
        }
    }
}
