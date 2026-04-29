//
//  PopupBlockedPopover.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa
import SwiftUI

final class PopupBlockedPopover: NSPopover {

    override init() {
        super.init()

        behavior = .applicationDefined
        contentViewController = PopupBlockedViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("PopupBlockedPopover: Bad initializer")
    }

    deinit {
#if DEBUG
        // Check that our content view controller deallocates
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    // swiftlint:disable force_cast
    var viewController: PopupBlockedViewController {
        get {
            if contentViewController == nil {
                contentViewController = PopupBlockedViewController()
            }
            return contentViewController as! PopupBlockedViewController
        }
    }
    // swiftlint:enable force_cast

}

final class PopupBlockedViewController: NSViewController {

    private var swiftUIHostingView: NSHostingView<PopupBlockedSwiftUIView>?
    private var dismissWorkItem: DispatchWorkItem?

    weak var query: PermissionAuthorizationQuery? {
        didSet {
            setupSwiftUIView()
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PopupBlockedViewController: Use init() instead")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView()
    }

    override func viewDidAppear() {
        // Cancel any existing work item to prevent multiple timers
        dismissWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: workItem)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func setupSwiftUIView() {
        view.subviews.forEach { $0.removeFromSuperview() }
        swiftUIHostingView = nil

        // Check if the popup has an empty or about: URL
        let isEmptyPopup: Bool = {
            guard let url = query?.url else { return true }
            return url.isEmpty || url.navigationalScheme == .about
        }()

        let swiftUIView = PopupBlockedSwiftUIView(
            isEmptyPopup: isEmptyPopup,
            onOpenClicked: { [weak self] in
                self?.handleOpen()
            }
        )

        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Set preferred content size for the popover
        let fittingSize = hostingView.fittingSize
        preferredContentSize = fittingSize

        swiftUIHostingView = hostingView
    }

    private func handleOpen() {
        dismiss()
        query?.handleDecision(grant: true)
    }
}

// MARK: - PopupBlockedSwiftUIView

struct PopupBlockedSwiftUIView: View {

    /// Whether the blocked popup has an empty or about: URL
    let isEmptyPopup: Bool
    let onOpenClicked: () -> Void

    private var buttonText: String {
        isEmptyPopup ? UserText.permissionPopupAllowPopupsButton : UserText.permissionPopupOpenButton
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(UserText.permissionPopupBlockedPopover)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Button(action: onOpenClicked) {
                Text(buttonText)
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .fixedSize()
    }
}
