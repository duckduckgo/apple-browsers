//
//  SyncOpenAppInstruction.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

struct SyncOpenAppInstruction: View {

    let format: String
    var appName: String = UserText.simplifiedViewCodeAppName

    var body: some View {
        text
            .daxSubheadRegular()
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: Text {
        let parts = format.components(separatedBy: "%@")
        let prefix = parts.first ?? ""
        let suffix = parts.dropFirst().joined()

        return Text(prefix)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            + Text(Image(uiImage: Self.appIcon))
                .baselineOffset(-3)
            + Text(verbatim: "\u{00A0}")
            + Text(appName)
                .fontWeight(.semibold)
                .foregroundColor(Color(designSystemColor: .textPrimary))
            + Text(suffix)
                .foregroundColor(Color(designSystemColor: .textSecondary))
    }

    private static let appIcon: UIImage = {
        let size = CGSize(width: 16, height: 16)
        return UIGraphicsImageRenderer(size: size).image { _ in
            DesignSystemImages.Color.Size24.appDuckDuckGo.draw(in: CGRect(origin: .zero, size: size))
        }
    }()
}

#Preview {
    SyncOpenAppInstruction(format: UserText.simplifiedEnterCodeOpenInstruction)
}
