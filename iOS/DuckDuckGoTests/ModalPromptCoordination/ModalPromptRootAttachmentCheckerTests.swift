//
//  ModalPromptRootAttachmentCheckerTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Root Attachment Checker")
final class ModalPromptRootAttachmentCheckerTests {
    private let sut: ModalPromptRootAttachmentChecker

    init() {
        sut = ModalPromptRootAttachmentChecker()
    }

    @available(iOS 16, *)
    @Test("Detached Root Is Not Attached", .timeLimit(.minutes(1)))
    func whenRootIsNotAttachedThenAttachmentCheckFails() {
        // GIVEN
        let root = UIViewController()

        // THEN
        #expect(!root.isBeingPresented)
        #expect(root.presentingViewController == nil)
        #expect(root.viewIfLoaded?.window == nil)
        #expect(!sut.isAttached(root))
    }
}
