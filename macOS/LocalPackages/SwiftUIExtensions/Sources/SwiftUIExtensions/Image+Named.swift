//
//  Image+Named.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension Image {

    public enum SystemImageName: String {
        case arrowCounterClockWise = "arrow.counterclockwise"
        case circleLeftHalfFilled = "circle.lefthalf.filled"
        case moon = "moon"
        case sunMax = "sun.max"
    }

    public init(systemNamed: SystemImageName) {
        self.init(systemName: systemNamed.rawValue)
    }

    public enum ImageName: String {
        case appearanceDark = "AppearanceDark"
        case appearanceLight = "AppearanceLight"
        case appearanceSystem = "AppearanceSystem"
    }

    public init(named: ImageName) {
        self.init(named.rawValue)
    }
}
