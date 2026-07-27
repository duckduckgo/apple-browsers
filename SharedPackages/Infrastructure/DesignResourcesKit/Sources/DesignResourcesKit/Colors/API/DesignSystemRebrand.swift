//
//  DesignSystemRebrand.swift
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

/// Whether the app is displaying the 2026 rebrand.
///
/// Kept as a convenience for the many call sites that need it.
/// This will disappear with the rest of the rebrand machinery once the flag is removed.
public enum DesignSystemRebrand {

    public static var isAppRebranded: () -> Bool {
        { DesignSystemPalette.current.isRebranded }
    }
}
