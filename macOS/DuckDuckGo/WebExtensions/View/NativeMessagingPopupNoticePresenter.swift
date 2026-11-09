//
//  NativeMessagingPopupNoticePresenter.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import WebExtensions
import WebKit

/// Adds a notice to an extension's popup while WebKit presents it.
@available(macOS 15.4, *)
@MainActor
protocol WebExtensionPopupNoticePresenting {
    /// Called before WebKit's popover is shown, while its content can still be replaced.
    func popupWillShow(_ popover: NSPopover, webView: WKWebView, for context: WKWebExtensionContext)
}

/// Tells the user, once per installed extension, that the extension tried to reach a desktop app,
/// which the App Store build can't allow.
///
/// WebKit's popover shows a plain view controller whose view is the popup web view, and resizes it to the
/// page through that controller's `preferredContentSize`. The banner goes in a container that stacks it
/// above WebKit's view controller and adds its height to every size WebKit asks for.
@available(macOS 15.4, *)
@MainActor
final class NativeMessagingPopupNoticePresenter: WebExtensionPopupNoticePresenting {
    private let noticeStore: NativeMessagingNoticeStoring
    private let themeManager: ThemeManager
    private var observations: [NSKeyValueObservation] = []

    init(noticeStore: NativeMessagingNoticeStoring, themeManager: ThemeManager) {
        self.noticeStore = noticeStore
        self.themeManager = themeManager
    }

    func popupWillShow(_ popover: NSPopover, webView: WKWebView, for context: WKWebExtensionContext) {
        observations = []
        guard noticeStore.needsNotice(for: context.uniqueIdentifier),
              let original = popover.contentViewController else { return }

        let container = NativeMessagingBannerContainerViewController(content: original, themeManager: themeManager)
        popover.contentViewController = container
        observations = [
            original.observe(\.preferredContentSize, options: [.initial, .new]) { [weak container] original, _ in
                MainActor.assumeMainThread {
                    container?.contentSizeDidChange(original.preferredContentSize)
                }
            },
            // The banner doesn't inherit the popover's appearance, so it follows the one set on the web view.
            webView.observe(\.appearance, options: [.initial, .new]) { [weak container] webView, _ in
                MainActor.assumeMainThread {
                    container?.view.appearance = webView.appearance
                }
            }
        ]
        noticeStore.markNoticeShown(for: context.uniqueIdentifier)
    }
}

/// Stacks the banner above the view controller WebKit created for the popup.
@available(macOS 15.4, *)
@MainActor
private final class NativeMessagingBannerContainerViewController: NSViewController {
    private let content: NSViewController
    private let themeManager: ThemeManager
    private var banner: NSHostingView<NativeMessagingBannerView>?

    init(content: NSViewController, themeManager: ThemeManager) {
        self.content = content
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = content.view
        let size = contentView.frame.size
        addChild(content)

        let banner = NSHostingView(rootView: NativeMessagingBannerView(themeManager: themeManager) { [weak self] in
            self?.removeBanner()
        })
        self.banner = banner

        let stack = NSStackView(views: [banner, contentView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        view = stack
        updateSize(for: size)
    }

    func contentSizeDidChange(_ size: NSSize) {
        guard isViewLoaded, size.width > 0, size.height > 0 else { return }
        updateSize(for: size)
    }

    private func updateSize(for contentSize: NSSize) {
        let bannerHeight = banner.map { bannerHeight(of: $0, width: contentSize.width) } ?? 0
        let size = NSSize(width: contentSize.width, height: contentSize.height + bannerHeight)
        guard preferredContentSize != size else { return }
        preferredContentSize = size
    }

    private func bannerHeight(of banner: NSView, width: CGFloat) -> CGFloat {
        banner.frame.size.width = width
        banner.layoutSubtreeIfNeeded()
        return banner.fittingSize.height
    }

    private func removeBanner() {
        guard let banner else { return }
        let contentSize = NSSize(width: view.frame.width, height: view.frame.height - banner.frame.height)
        banner.removeFromSuperview()
        self.banner = nil
        updateSize(for: contentSize)
    }
}

@available(macOS 15.4, *)
private struct NativeMessagingBannerView: View {
    @ObservedObject var themeManager: ThemeManager
    let onDismiss: () -> Void

    private var palette: DesignResourcesKit.ColorPalette {
        themeManager.designColorPalette
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.info)
                .foregroundColor(Color(designSystemColor: .iconsSecondary, palette: palette))
            Text(UserText.webExtensionNativeMessagingBannerMessage)
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary, palette: palette))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UserText.webExtensionNativeMessagingBannerDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 280, maxWidth: 400)
        .background(Color(designSystemColor: .surfaceSecondary, palette: palette))
    }
}
