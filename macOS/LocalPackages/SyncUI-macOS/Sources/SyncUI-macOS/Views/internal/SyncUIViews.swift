//
//  SyncUIViews.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

/// Shared Sync text styles. Each component retains its own typography and alignment.
enum SyncUIViews {

    struct DialogTitle: View {
        let text: String

        var body: some View {
            Text(text)
                .bold()
                .font(.system(size: 17))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct DialogMessage: View {
        let text: String

        var body: some View {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct CenteredTitle: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct SectionHeading: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    struct CenteredBody: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct CenteredMarkdownBody: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct CenteredSecondaryBody: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
    }

    struct LeadingSecondaryBody: View {
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

    struct Caption: View {
        let text: String

        var body: some View {
            Text(.init(text))
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
