//
//  NewReportFeedbackView.swift
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

import SwiftUI
import BrowserServicesKit
import DesignResourcesKit

struct NewReportFeedbackView: View {

    @Binding var model: DataImportReportModel

    @State var isShowingDetail: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UserText.importSummarySendFeedbackTitle)
                .font(.system(size: 17, weight: .bold))
                .padding(.bottom, 10)

            EditableTextView(text: $model.text,
                             font: .systemFont(ofSize: 13),
                             insets: NSSize(width: 7, height: 12),
                             cornerRadius: 6,
                             backgroundColor: .textBackgroundColor,
                             textColor: .textColor,
                             focusRingType: .exterior,
                             isFocusedOnAppear: true)
            .frame(height: 114)
            .shadow(color: Color.addressBarShadow, radius: 1, x: 0, y: 1)
            .overlay(
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        Text(UserText.importSummarySendFeedbackFieldPlaceholderText)
                        .foregroundColor(Color(.placeholderTextColor))
                        .padding(.leading, 11)
                        Spacer()
                    }
                    .padding(.top, 11)
                    Spacer()
                }
                    .visibility(model.text.isEmpty ? .visible : .gone)
                    .allowsHitTesting(false)
            )

            HStack(spacing: 1) {
                Text(UserText.importSummarySendFeedbackAnonymousReports)
                    .font(.system(size: 11))
                    .foregroundColor(Color(designSystemColor: .textTertiary))
                if !isShowingDetail {
                    Button(UserText.importSummarySendFeedbackShowsDetailButtonTitle) {
                        isShowingDetail.toggle()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Color(designSystemColor: .accentSecondary))
                    .buttonStyle(.plain)
                }
            }
            if isShowingDetail {
                InfoItemView(model.osVersion) {
                    Text("macOS version", comment: "Data import failure Report dialog description of a report field providing user‘s macOS version")
                }
                InfoItemView(model.appVersion) {
                    Text("DuckDuckGo browser version", comment: "Data import failure Report dialog description of a report field providing current DuckDuckGo Browser version")
                }
                InfoItemView(model.importSourceDescription) {
                    Text("The version of the browser you are trying to import from", comment: "Data import failure Report dialog description of a report field providing version of a browser user is trying to import data from")
                }
                InfoItemView(model.error.localizedDescription) {
                    Text("Error message & code", comment: "Title of the section of a dialog (form where the user can report feedback) where the error message and the error code are shown")
                }
            }
        }
    }

}

private struct InfoItemView: View {

    let text: () -> Text
    let data: String
    @State private var isPopoverVisible = false

    init(_ data: String, text: @escaping () -> Text) {
        self.text = text
        self.data = data
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isPopoverVisible.toggle()
            } label: {
                Image(.infoLight)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isPopoverVisible, arrowEdge: .bottom) {
                Text(data).padding()
            }

            text()
        }
    }

}
