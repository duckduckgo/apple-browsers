//
//  SyncUIViewsV2.swift
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
import DesignResourcesKit

/// V2 of the shared Sync text components, gated behind the `simplifiedSyncSetupV2` feature flag.
/// Mirrors the structure of `SyncUIViews` but adopts the type ramp and semantic colors from the
/// "Encourage Sync cross-device activations" Figma designs.
enum SyncUIViewsV2 {

    struct TextHeader: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct TextHeader2: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    struct TextDetailMultiline: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct TextDetailMultilineMarkdown: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct TextDetailSecondary: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct TextDetailSecondaryLeftAligned: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    struct TextLink: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textLink))
        }
    }

    struct TextCaption: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
