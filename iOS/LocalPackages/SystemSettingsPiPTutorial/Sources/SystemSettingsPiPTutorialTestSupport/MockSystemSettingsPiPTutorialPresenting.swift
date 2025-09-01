//
//  MockSystemSettingsPiPTutorialPresenting.swift
//  DuckDuckGo
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

import UIKit
@testable import SystemSettingsPiPTutorial

public final class MockSystemSettingsPiPTutorialPresenting: SystemSettingsPiPTutorialPresenting {
    public private(set) var didCallAttachPlayerView: Bool = false
    public private(set) var didCallDetachPlayerView: Bool = false
    public private(set) var capturedPlayerView: UIView?

    public init() {}

    public func attachPlayerView(_ view: UIView) {
        didCallAttachPlayerView = true
        capturedPlayerView = view
    }
    
    public func detachPlayerView(_ view: UIView) {
        didCallDetachPlayerView = true
        capturedPlayerView = view
    }
}
