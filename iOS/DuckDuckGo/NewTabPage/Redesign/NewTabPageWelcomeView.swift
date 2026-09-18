//
//  NewTabPageWelcomeView.swift
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
import SwiftUI

struct NewTabPageWelcomeView: View {

    @ObservedObject var model: NewTabPageWelcomeModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: Metrics.logoToTextSpacing) {
            Image("Logo")
                .resizable()
                .frame(width: Metrics.logoSize, height: Metrics.logoSize)
            Text(verbatim: model.greeting)
                .daxTitle2()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .padding(.horizontal, Metrics.horizontalMargin)
        .onAppear {
            isVisible = true
            refreshGreeting()
        }
        .onDisappear { isVisible = false }
        .onReceive(model.contextChanges) { _ in refreshGreetingIfVisible() }
        .onChange(of: colorScheme) { _ in refreshGreetingIfVisible() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshGreetingIfVisible()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshGreetingIfVisible()
        }
    }

    private func refreshGreetingIfVisible() {
        guard isVisible else { return }
        refreshGreeting()
    }

    private func refreshGreeting() {
        model.refresh(appearance: colorScheme == .dark ? .dark : .light)
    }
}

private enum Metrics {
    static let horizontalMargin: CGFloat = 16
    static let horizontalPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 20
    static let logoSize: CGFloat = 64
    static let logoToTextSpacing: CGFloat = 16
}

#Preview {
    NewTabPageWelcomeView(model: NewTabPageWelcomeModel(greetingProvider: DaxGreetingService(), updateAppearance: { _ in }))
}
