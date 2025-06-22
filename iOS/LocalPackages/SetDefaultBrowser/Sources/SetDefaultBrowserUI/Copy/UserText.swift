//
//  UserText.swift
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

enum UserText {

    enum ModalSheet {
        static let title = NSLocalizedString("setDefaultBrowser.modal.title", bundle: Bundle.module, value: "Let DuckDuckGo protect more of what you do online", comment: "Set Default Browser Modal Sheet Title.")
        static let message = NSLocalizedString("setDefaultBrowser.modal.message", bundle: Bundle.module, value: "Make us your default browser so all site links open in DuckDuckGo", comment: "Set Default Browser Modal Sheet Message.")
        static let cancelCTA = NSLocalizedString("setDefaultBrowser.modal.cta.cancel", bundle: Bundle.module, value: "Cancel", comment: "The title of the button to dismiss the modal sheet.")
    }

    enum Banner {

    }

    enum CTA {
        static let primary = NSLocalizedString("setDefaultBrowser.cta.primary.title", bundle: Bundle.module, value: "Set As Default Browser", comment: "The tile of the CTA to set the browser as default.")
        static let secondary = NSLocalizedString("setDefaultBrowser.cta.secondary.title", bundle: Bundle.module, value: "Don’t Ask Again", comment: "The title of the CTA to permanently dismiss the modal sheet.")
    }

}
