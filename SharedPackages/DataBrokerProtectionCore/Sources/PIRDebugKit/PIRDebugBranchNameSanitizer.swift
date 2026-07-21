//
//  PIRDebugBranchNameSanitizer.swift
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

/// Mirrors dbp-api's branch-name sanitization (`upload_remote_configuration_pr.yml`):
/// lowercase, then replace every character outside `[a-z0-9.-]` with `-`.
/// e.g. `randerson/fix-foo` -> `randerson-fix-foo`.
public enum PIRDebugBranchNameSanitizer {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")

    public static func sanitize(_ branchName: String) -> String {
        String(branchName.lowercased().map { allowed.contains($0) ? $0 : "-" })
    }
}
