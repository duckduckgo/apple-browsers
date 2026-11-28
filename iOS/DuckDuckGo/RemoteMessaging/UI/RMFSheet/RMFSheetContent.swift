//
//  RMFSheetContent.swift
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

import SwiftUI

/// Everything an RMF sheet can show. Text is displayed exactly as given, with no case conversion.
struct RMFSheetContent {

    enum Height {
        /// Fits its content, up to the height of the screen.
        case content
        /// Full height, with the actions pinned to the bottom.
        case full
    }

    struct Label {
        enum Style {
            /// Yellow pill above the title.
            case new
            /// Grey text below the title.
            case subtle
        }

        let text: String
        let style: Style
    }

    /// A sheet always keeps a way out: the close button, the secondary button, or both.
    enum Exit {
        case closeButton
        case secondaryButton(String)
        case closeAndSecondaryButton(String)

        var showsCloseButton: Bool {
            switch self {
            case .closeButton, .closeAndSecondaryButton: return true
            case .secondaryButton: return false
            }
        }

        var secondaryButtonTitle: String? {
            switch self {
            case .closeButton: return nil
            case .secondaryButton(let title), .closeAndSecondaryButton(let title): return title
            }
        }
    }

    /// A single-select list of 2 or 3 choices with one preselected.
    struct ChoiceList {
        struct Choice: Identifiable, Equatable {
            let id: String
            let title: String
            let description: String?
        }

        let choices: [Choice]
        let preselectedID: Choice.ID

        init?(choices: [Choice], preselectedID: Choice.ID) {
            guard (2...3).contains(choices.count),
                  Set(choices.map(\.id)).count == choices.count,
                  choices.contains(where: { $0.id == preselectedID }) else { return nil }
            self.choices = choices
            self.preselectedID = preselectedID
        }
    }

    var height: Height = .content
    var media: Image?
    var label: Label?
    let title: String
    var body: String?
    var choiceList: ChoiceList?
    let primaryButtonTitle: String
    let exit: Exit
    var footnote: String?
}

enum RMFSheetAction: Equatable {
    /// Carries the selected choice when the sheet has a choice list.
    case primary(selectedChoiceID: String?)
    case secondary
    case close
}
