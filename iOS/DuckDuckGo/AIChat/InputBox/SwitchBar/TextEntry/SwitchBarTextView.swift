//
//  SwitchBarTextView.swift
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
import SwiftUI
import Combine
import DesignResourcesKitIcons

final class SwitchBarTextView: UITextView {

    var onTouchesBeganHandler: (() -> Void)?

    /// You'd think a gesture would be useful here, but it stops the menu from appearing, even if you tell it not to cancel touches, or if you tell it to delay touch begin/end.
    ///   So this is a little work around that does the job.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onTouchesBeganHandler?()
    }

}
