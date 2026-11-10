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

/// Tells the user that an installed extension tried to reach a desktop app, which the App Store build
/// can't allow. The banner shows each time the popup opens until the user dismisses it.
///
/// WebKit's popover shows a plain view controller whose view is the popup web view, and resizes it to the
/// page through that controller's `preferredContentSize`. The banner goes in a container that lays it out
/// above WebKit's view and adds its height to every size WebKit asks for.
@available(macOS 15.4, *)
@MainActor
final class NativeMessagingPopupNoticePresenter: WebExtensionPopupNoticePresenting {
    private let noticeStore: NativeMessagingNoticeStoring
    private let themeManager: ThemeManager
    private let openURL: (URL) -> Void
    private var observations: [NSKeyValueObservation] = []

    init(
        noticeStore: NativeMessagingNoticeStoring,
        themeManager: ThemeManager,
        openURL: @escaping (URL) -> Void
    ) {
        self.noticeStore = noticeStore
        self.themeManager = themeManager
        self.openURL = openURL
    }

    func popupWillShow(_ popover: NSPopover, webView: WKWebView, for context: WKWebExtensionContext) {
        observations = []
        guard noticeStore.needsNotice(for: context.uniqueIdentifier),
              let original = popover.contentViewController else { return }

        let identifier = context.uniqueIdentifier
        let container = NativeMessagingBannerContainerViewController(
            content: original,
            themeManager: themeManager,
            onOpenURL: { [weak popover, openURL] url in
                popover?.performClose(nil)
                openURL(url)
            },
            onDismiss: { [noticeStore] in
                noticeStore.markNoticeShown(for: identifier)
            }
        )
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
    }
}

/// Lays the banner out above the view controller WebKit created for the popup.
///
/// WebKit's view keeps the size WebKit asks for, and the container's height comes from Auto Layout, so the
/// banner gets the height its wrapped text needs at the popup's width.
@available(macOS 15.4, *)
@MainActor
private final class NativeMessagingBannerContainerViewController: NSViewController {
    private let content: NSViewController
    private let themeManager: ThemeManager
    private let onOpenURL: (URL) -> Void
    private let onDismiss: () -> Void
    private var banner: NSView?
    private var contentWidthConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var contentTopConstraint: NSLayoutConstraint?

    init(
        content: NSViewController,
        themeManager: ThemeManager,
        onOpenURL: @escaping (URL) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.content = content
        self.themeManager = themeManager
        self.onOpenURL = onOpenURL
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = content.view
        let size = contentView.frame.size
        addChild(content)

        let banner = NSHostingView(rootView: NativeMessagingBannerView(
            themeManager: themeManager,
            onOpenURL: { [weak self] url in self?.onOpenURL(url) },
            onDismiss: { [weak self] in self?.removeBanner() }
        ))
        self.banner = banner

        let container = NSView()
        for subview in [banner, contentView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        let contentTopConstraint = contentView.topAnchor.constraint(equalTo: banner.bottomAnchor)
        let contentWidthConstraint = contentView.widthAnchor.constraint(equalToConstant: size.width)
        let contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: size.height)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: container.topAnchor),
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentWidthConstraint,
            contentHeightConstraint
        ])
        self.contentTopConstraint = contentTopConstraint
        self.contentWidthConstraint = contentWidthConstraint
        self.contentHeightConstraint = contentHeightConstraint
        view = container
        updateSize(for: size)
    }

    func contentSizeDidChange(_ size: NSSize) {
        guard isViewLoaded, size.width > 0, size.height > 0 else { return }
        updateSize(for: size)
    }

    private func updateSize(for contentSize: NSSize) {
        contentWidthConstraint?.constant = contentSize.width
        contentHeightConstraint?.constant = contentSize.height
        let size = NSSize(width: contentSize.width, height: view.fittingSize.height)
        guard preferredContentSize != size else { return }
        preferredContentSize = size
    }

    private func removeBanner() {
        guard let banner, let contentHeightConstraint, let contentWidthConstraint else { return }
        contentTopConstraint?.isActive = false
        banner.removeFromSuperview()
        self.banner = nil
        let contentTopConstraint = content.view.topAnchor.constraint(equalTo: view.topAnchor)
        contentTopConstraint.isActive = true
        self.contentTopConstraint = contentTopConstraint
        updateSize(for: NSSize(width: contentWidthConstraint.constant, height: contentHeightConstraint.constant))
        onDismiss()
    }
}

@available(macOS 15.4, *)
private struct NativeMessagingBannerView: View {
    private static let downloadURL = URL(string: "https://duckduckgo.com/mac")!

    @ObservedObject var themeManager: ThemeManager
    let onOpenURL: (URL) -> Void
    let onDismiss: () -> Void

    private var palette: DesignResourcesKit.ColorPalette {
        themeManager.designColorPalette
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: DesignSystemImages.Color.Size16.exclamationMedium)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(UserText.webExtensionNativeMessagingBannerTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    message
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                        .foregroundColor(Color(designSystemColor: .iconsSecondary, palette: palette))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UserText.webExtensionNativeMessagingBannerDismiss)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            Rectangle()
                .fill(Color(designSystemColor: .surfaceDecorationPrimary, palette: palette))
                .frame(height: 1)
        }
        .environment(\.openURL, OpenURLAction { url in
            onOpenURL(url)
            return .handled
        })
    }

    private var message: Text {
        var link = AttributedString(Self.downloadURL.absoluteString)
        link.link = Self.downloadURL
        link.foregroundColor = Color(designSystemColor: .accentPrimary, palette: palette)
        return Text(UserText.webExtensionNativeMessagingBannerMessage + " ") + Text(link)
    }
}
