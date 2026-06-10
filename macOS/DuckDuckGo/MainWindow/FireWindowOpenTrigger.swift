//
//  FireWindowOpenTrigger.swift
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

/// Identifies how a Fire Window was opened.
enum FireWindowOpenTrigger: String, CustomStringConvertible {
    var description: String { rawValue }

    /// User explicitly chose to open a Fire Window — e.g. overflow menu,
    /// main menu, dock menu, context menu, Fire popover, history view.
    case manual

    /// Fire Window opened without an explicit "Open Fire Window" choice —
    /// "Open Fire Window by default" preference or the startup window type set to Fire Window.
    case automatic
}
