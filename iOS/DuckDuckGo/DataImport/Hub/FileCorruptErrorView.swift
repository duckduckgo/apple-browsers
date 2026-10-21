//
//  FileCorruptErrorView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI

struct FileCorruptErrorView: View {

    let title: String
    let message: String
    var onGotIt: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)

            Image(uiImage: DesignSystemImages.Color.Size128.fileIssue)
                .padding(.bottom, 24)

            Text(title)
                .daxTitle1()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            Text(message)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Spacer()

            Button {
                onGotIt?()
            } label: {
                Text(UserText.fileImportErrorButton)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(designSystemColor: .background))
    }
}

@available(iOS 16.0, *)
#Preview {
    FileCorruptErrorView(
        title: "File may be corrupt",
        message: "Try uploading another file or try another import method.")
}
