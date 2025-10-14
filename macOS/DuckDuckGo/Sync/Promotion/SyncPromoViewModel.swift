//
//  SyncPromoViewModel.swift
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

struct SyncPromoViewModel {

    var touchpointType: SyncPromoManager.Touchpoint = .bookmarks

    var primaryButtonAction: (() -> Void)?
    var dismissButtonAction: (() -> Void)?

    var title: String {
        switch touchpointType {
        case .bookmarks:
            UserText.syncPromoBookmarksTitle
        case .passwords:
            UserText.syncPromoPasswordsTitle
        case .autofill:
            UserText.syncPromoAutofillTitle
        case .creditCards:
            UserText.syncPromoCreditCardsTitle
        case .identities:
            UserText.syncPromoIdentitiesTitle
        }
    }

    var subtitle: String {
        UserText.syncPromoMessage
    }

    var image: String {
        switch touchpointType {
        default:
            return "Sync-OK-96x96"
        }
    }

    var primaryButtonTitle: String {
        switch touchpointType {
        default:
            UserText.syncPromoConfirmAction
        }
    }

    var secondaryButtonTitle: String {
        switch touchpointType {
        default:
            UserText.syncPromoDismissAction
        }
    }
}
