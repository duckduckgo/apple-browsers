//
//  ModalPromptRootAttachmentChecker.swift
//  DuckDuckGo
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

import UIKit

@MainActor
protocol ModalPromptRootAttachmentChecking {
    func isAttached(_ root: UIViewController) -> Bool
}

struct ModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {

    /// A root remains attached throughout dismissal while UIKit still presents it or keeps its view in a window.
    ///
    /// `isBeingDismissed` becomes true at the start of the animation, before the modal has left the screen. The concrete
    /// presentation and window relationships are the source of truth so the modal lease cannot be released while the
    /// outgoing root can still overlap a newly admitted promo.
    func isAttached(_ root: UIViewController) -> Bool {
        return root.isBeingPresented || root.presentingViewController != nil || root.viewIfLoaded?.window != nil
    }
}
