//
//  ContentSecurityPolicy.swift
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

public enum ContentSecurityPolicy {
    /// Pass the enforced `Content-Security-Policy` header, never `-Report-Only`. Policies are
    /// comma-separated and directives semicolon-separated, so any piece named `sandbox` counts.
    public static func declaresSandbox(_ header: String?) -> Bool {
        (header ?? "").split(whereSeparator: { $0 == "," || $0 == ";" }).contains { directive in
            directive.split(whereSeparator: \.isWhitespace).first?.lowercased() == "sandbox"
        }
    }
}
