//
//  SyncPromoViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SwiftUI

struct SyncPromoViewModel {

    var touchpointType: SyncPromoManager.Touchpoint = .bookmarks
    var design: SyncPromoManager.Design = .standard

    var primaryButtonAction: (() -> Void)?
    var dismissButtonAction: (() -> Void)?

    var title: String {
        switch touchpointType {
        case .bookmarks:
            UserText.syncPromoBookmarksTitle
        case .passwords:
            UserText.syncPromoPasswordsTitle
        case .dataImport, .aiChat:
            ""
        }
    }

    var subtitle: String {
        switch (touchpointType, design) {
        case (.bookmarks, .redesigned):
            UserText.syncPromoBookmarksRedesignMessage
        case (.bookmarks, .standard):
            UserText.syncPromoBookmarksMessage
        case (.passwords, _):
            UserText.syncPromoPasswordsMessage
        case (.dataImport, _), (.aiChat, _):
            ""
        }
    }

    var image: String {
        switch design {
        case .standard:
            "Sync-Pending-96"
        case .redesigned:
            "Sync-Pending-Feature-96"
        }
    }

    var primaryButtonTitle: String {
        switch design {
        case .standard:
            UserText.syncPromoConfirmAction
        case .redesigned:
            UserText.syncPromoTurnOnAction
        }
    }

    var secondaryButtonTitle: String? {
        switch design {
        case .standard:
            UserText.syncPromoDismissAction
        case .redesigned:
            nil
        }
    }
}
