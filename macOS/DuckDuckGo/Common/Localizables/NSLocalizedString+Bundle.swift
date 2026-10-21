//
//  NSLocalizedString+Bundle.swift
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

/// Looks strings up in the bundle of the module that calls it (`#bundle` expands at the call site):
/// the main bundle in an app target, `Bundle.module` in a Swift package.
/// Declared in the module, it shadows Foundation's `NSLocalizedString`, so existing calls don't pass a bundle.
/// Xcode still extracts the calls into the string catalog: extraction matches the function name.
func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = #bundle, value: String = "", comment: String) -> String {
    Foundation.NSLocalizedString(key, tableName: tableName, bundle: bundle, value: value, comment: comment)
}
