//
//  Global.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import SwiftUI

public func isIPhonePortrait(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?) -> Bool {
    v == .regular && h == .compact
}

public func isIPhoneLandscape(v: UserInterfaceSizeClass?) -> Bool {
    v == .compact
}

public func isIPad(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?) -> Bool {
    v == .regular && h == .regular
}

@MainActor
public func isIPadLandscape(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?, screenSize: CGSize = UIScreen.main.bounds.size) -> Bool {
    isIPad(v: v, h: h) && screenSize.width > screenSize.height
}
