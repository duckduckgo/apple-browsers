//
//  OpenAIChatFromAddressBarHandling.swift
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

import Foundation

class OpenAIChatFromAddressBarHandling {

    func determineOpeningStrategy(isTextFieldEditing: Bool, textFieldValue: String?, currentURL: URL?,
                                  openWithPromptAndSend: (String) -> Void,
                                  open: () -> Void) {

        // https://app.asana.com/0/1204167627774280/1209322943444951
        // Superceded by: https://app.asana.com/1/137249556945/project/392891325557410/task/1210888855345533?focus=true

        guard isTextFieldEditing,
                let textFieldValue,
                !textFieldValue.trimmingWhitespace().isEmpty else {
            open()
            return
        }

        if let currentURLString = currentURL?.absoluteString, currentURLString == textFieldValue {
            openWithPromptAndSend(currentURLString.dropping(prefix: currentURL?.navigationalScheme?.separated() ?? ""))
        } else {
            openWithPromptAndSend(textFieldValue)
        }
    }

}
