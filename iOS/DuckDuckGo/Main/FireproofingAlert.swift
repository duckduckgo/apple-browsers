//
//  FireproofingAlert.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Core

class FireproofingAlert {

    static func showFireproofDisabledMessage(forDomain domain: String) {
        let message = UserText.fireproofingRemovalConfirmMessage.format(arguments: domain)
        ActionMessageView.present(message: message)
    }

    static func showFireproofEnabledMessage(forDomain domain: String) {
        let message = UserText.fireproofingConfirmMessage.format(arguments: domain)
        ActionMessageView.present(message: message)
    }
    
    static func showConfirmFireproofWebsite(usingController controller: UIViewController,
                                            forDomain domain: String,
                                            onConfirmHandler: @escaping () -> Void) {
        let prompt = UIAlertController(title: UserText.fireproofingAskTitle.format(arguments: domain),
                                       message: UserText.fireproofingAskMessage,
                                       preferredStyle: controller.isPad ? .alert : .actionSheet)
        prompt.addAction(title: UserText.FireproofingConfirmAction, style: .default) {
            onConfirmHandler()
        }
        prompt.addAction(title: UserText.actionCancel, style: .cancel)
        controller.present(prompt, animated: true)
    }
    
    static func showFireproofWebsitePrompt(usingController controller: UIViewController,
                                           forDomain domain: String,
                                           onConfirmHandler: @escaping () -> Void) {
        let prompt = UIAlertController(title: UserText.fireproofingAskTitle.format(arguments: domain),
                                       message: UserText.fireproofingAskMessage,
                                       preferredStyle: controller.isPad ? .alert : .actionSheet)
        prompt.addAction(title: UserText.FireproofingConfirmAction) {
            onConfirmHandler()
        }
        prompt.addAction(title: UserText.fireproofingDeferAction, style: .cancel)
        controller.present(prompt, animated: true)
    }
    
    static func showClearAllAlert(usingController controller: UIViewController, cancelled: @escaping () -> Void, confirmed: @escaping () -> Void) {
        
        if controller.isPad {
            let alert = UIAlertController(title: UserText.fireproofingRemoveAllTitle, message: nil, preferredStyle: .alert)
            alert.addAction(title: UserText.fireproofingRemoveAllOk, style: .destructive) {
                confirmed()
            }
            alert.addAction(title: UserText.actionCancel, style: .cancel) {
                cancelled()
            }
            controller.present(alert, animated: true)
        } else {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            alert.addAction(title: UserText.fireproofingRemoveAllTitle, style: .destructive) {
                confirmed()
            }
            alert.addAction(title: UserText.actionCancel, style: .cancel) {
                cancelled()
            }
            controller.present(alert, animated: true)
        }
        
    }
    
}
