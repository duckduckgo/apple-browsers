//
//  AIChatSidebar.swift
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

import Foundation

/// A wrapper class that represents the AI Chat sidebar contents and its displayed view controller.
final class AIChatSidebar {
    /// The view controller that displays the sidebar contents.
    var sidebarViewController: AIChatSidebarViewController

    /// Creates a sidebar wrapper with the specified view controller.
    /// - Parameter sidebarViewController: The view controller to display. Defaults to a new instance.
    init(sidebarViewController: AIChatSidebarViewController = AIChatSidebarViewController()) {
        self.sidebarViewController = sidebarViewController
    }
}
