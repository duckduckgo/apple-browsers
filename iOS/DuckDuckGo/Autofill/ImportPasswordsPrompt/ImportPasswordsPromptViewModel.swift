//
//  ImportPasswordsPromptViewModel.swift
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

protocol ImportPasswordsPromptViewModelDelegate: AnyObject {
    func importPasswordsPromptViewModelDidSelectImportPasswords(_ viewModel: ImportPasswordsPromptViewModel)
    func importPasswordsPromptViewModelDidSelectSetUpLater(_ viewModel: ImportPasswordsPromptViewModel)
    func importPasswordsPromptViewModelDidDismiss(_ viewModel: ImportPasswordsPromptViewModel)
    func importPasswordsPromptViewModelDidResizeContent(_ viewModel: ImportPasswordsPromptViewModel, contentHeight: CGFloat)
}

class ImportPasswordsPromptViewModel: ObservableObject {
    weak var delegate: ImportPasswordsPromptViewModelDelegate?

    var contentHeight: CGFloat = AutofillViews.passwordGenerationMinHeight {
        didSet {
            guard contentHeight != oldValue else {
                return
            }
            delegate?.importPasswordsPromptViewModelDidResizeContent(self,
                                                                     contentHeight: max(contentHeight, AutofillViews.passwordGenerationMinHeight))
        }
    }

    func importPasswordsPressed() {
        delegate?.importPasswordsPromptViewModelDidSelectImportPasswords(self)
    }

    func setUpLaterButtonPressed() {
        delegate?.importPasswordsPromptViewModelDidSelectSetUpLater(self)
    }

    func dismissButtonPressed() {
        delegate?.importPasswordsPromptViewModelDidDismiss(self)
    }
}
