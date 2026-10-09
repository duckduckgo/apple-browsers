//
//  DBPUIOptOutEmailWorkspace.swift
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

import AppKit
import Foundation

protocol DBPUIOptOutEmailWorkspace {
    @MainActor
    func defaultMailAppBundleIdentifier() -> String?
    @MainActor
    func open(_ url: URL) -> Bool
}

final class DBPUIOptOutEmailNSWorkspace: DBPUIOptOutEmailWorkspace {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    @MainActor
    func defaultMailAppBundleIdentifier() -> String? {
        guard let mailtoURL = URL(string: "mailto:test@example.com"),
              let applicationURL = workspace.urlForApplication(toOpen: mailtoURL) else {
            return nil
        }

        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    @MainActor
    func open(_ url: URL) -> Bool {
        workspace.open(url)
    }
}
