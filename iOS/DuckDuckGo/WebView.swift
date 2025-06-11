//
//  WebView.swift
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
import WebKit
import os.log

final class WebView: WKWebView {
    private lazy var accessory = KeyboardInputAccessoryView()
    var suppressSystemInputView: Bool = false
    private var lastAccessoryState: String = ""

    override var inputAccessoryView: UIView? {
       let hasContent = accessory.currentContent != nil
       let returnValue: UIView?

        if hasContent || suppressSystemInputView {
           returnValue = accessory
       } else {
           returnValue = super.inputAccessoryView
       }

       // Create state string that's always comparable
       let currentState = createStateString(returnValue, isCustom: hasContent)

       if lastAccessoryState != currentState {
           Logger.autofill.debug("🔄 ACCESSORY CHANGE: \(self.lastAccessoryState) -> \(currentState)")
           lastAccessoryState = currentState
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
               Logger.autofill.debug("Delayed reload after update")
               self.reloadContentViewInputViews()
           }
       }

       return returnValue
    }

    private func createStateString(_ accessory: UIView?, isCustom: Bool) -> String {
        if let accessory = accessory {
            let id = ObjectIdentifier(accessory)
            return "\(isCustom ? "custom" : "system"):\(id)"
        } else {
            return "nil"
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }

    func setAccessoryContentView(_ contentView: UIView, height: CGFloat) {
        Logger.autofill.debug("Setting accessory content view")
        accessory.setContentView(contentView, contentHeight: height)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Logger.autofill.debug("Delayed reload after keyboard stabilization")
            self.reloadContentViewInputViews()
        }
    }

    func removeAccessoryContentView() {
        Logger.autofill.debug("Removing accessory content view")
        guard accessory.currentContent != nil else { return }
        
        accessory.setContentView(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.reloadContentViewInputViews()
        }
    }

    private func reloadContentViewInputViews() {
        guard let content = scrollView.subviews.first(
            where: { String(describing: type(of: $0))
                .hasPrefix("WKContent") })
        else { return }
        content.reloadInputViews()
    }
}
