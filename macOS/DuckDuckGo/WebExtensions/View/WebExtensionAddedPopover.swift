//
//  WebExtensionAddedPopover.swift
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

import AppKit
import Combine
import DesignResourcesKit
import SwiftUI

/// Points the user to a newly installed extension's button. Closes on its own unless the pointer reaches it.
final class WebExtensionAddedPopoverViewController: NSHostingController<WebExtensionAddedPopoverView> {

    private enum Constants {
        static let autoDismissDuration: TimeInterval = 5
    }

    private var autoDismissTimer: Timer?
    private var themeCancellable: AnyCancellable?

    init(extensionName: String, iconProvider: (CGSize) -> NSImage?, themeManager: ThemeManaging) {
        super.init(rootView: WebExtensionAddedPopoverView(title: String(format: UserText.webExtensionAddedTitle, extensionName),
                                                          message: UserText.webExtensionAddedMessage,
                                                          icon: iconProvider(WebExtensionAddedPopoverView.Constants.iconSize),
                                                          palette: themeManager.theme.name.designColorPalette))

        rootView.onHover = { [weak self] in
            self?.cancelAutoDismiss()
        }
        themeCancellable = themeManager.themePublisher
            .dropFirst()
            .sink { [weak self] theme in
                self?.rootView.palette = theme.name.designColorPalette
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: Constants.autoDismissDuration, repeats: false) { [weak self] _ in
            self?.dismiss(nil)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        cancelAutoDismiss()
    }

    func show(onParent parent: NSViewController, relativeTo view: NSView) {
        self.view.frame.size = self.view.fittingSize
        preferredContentSize = self.view.fittingSize
        // The positioning can be off unless the width is set a second time.
        preferredContentSize.width = self.view.fittingSize.width
        parent.present(self, asPopoverRelativeTo: view.bounds, of: view, preferredEdge: .maxY, behavior: .transient)
    }

    private func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
}

struct WebExtensionAddedPopoverView: View {

    fileprivate enum Constants {
        static let iconSize = CGSize(width: 48, height: 48)
        static let iconContainerSize: CGFloat = 69
        static let iconContainerCornerRadius: CGFloat = 16
        static let padding: CGFloat = 16
        static let titleBottomPadding: CGFloat = 10
        static let descriptionBottomPadding: CGFloat = 10
        static let textTrailingPadding: CGFloat = 24
        static let textWidth: CGFloat = 300
    }

    let title: String
    let message: String
    let icon: NSImage?
    var palette: DesignResourcesKit.ColorPalette
    var onHover: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            iconContainer
                .padding(Constants.padding)

            // At least as tall as the icon container, so a short message lines up with its bottom.
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Constants.titleBottomPadding)
                Spacer(minLength: 0)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Constants.descriptionBottomPadding)
            }
            .frame(width: Constants.textWidth, alignment: .leading)
            .frame(minHeight: Constants.iconContainerSize)
            .padding(.vertical, Constants.padding)
            .padding(.trailing, Constants.textTrailingPadding)
        }
        .onHover { isHovered in
            if isHovered {
                onHover()
            }
        }
    }

    private var iconContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.iconContainerCornerRadius)
                .fill(Color(designSystemColor: .controlsSubtleFillSecondary, palette: palette))
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Constants.iconSize.width, height: Constants.iconSize.height)
            }
        }
        .frame(width: Constants.iconContainerSize, height: Constants.iconContainerSize)
    }
}
