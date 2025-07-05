//
//  SwitchBarViewController.swift
//  DuckDuckGo
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

import UIKit
import SwiftUI
import Combine
import DesignResourcesKitIcons
import UIComponents

class SwitchBarViewController: UIViewController {
    private struct Constants {
        static let segmentedControlHeight: CGFloat = 36
        static let segmentedControlTopPadding: CGFloat = 20
        static let textEntryViewTopPadding: CGFloat = 16
        static let textEntryViewSidePadding: CGFloat = 16
        static let backButtonHorizontalPadding: CGFloat = 16
    }

    private var segmentedPickerHostingController: UIHostingController<PickerWrapper>?
    let textEntryViewController: SwitchBarTextEntryViewController
    let backButton = BrowserChromeButton(.secondary)

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()
    
    private var segmentedControlTopConstraint: NSLayoutConstraint?

    private var isExpanded = false
    
    // Items for the segmented picker
    private let pickerItems = [
        ImageSegmentedPickerItem(
            text: "Search",
            selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearchGradientColor),
            unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearch)
        ),
        ImageSegmentedPickerItem(
            text: "Duck.ai",
            selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChatGradientColor),
            unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChat)
        )
    ]
    private var pickerState: PickerState?

    // MARK: - Initialization
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        self.textEntryViewController = SwitchBarTextEntryViewController(handler: switchBarHandler)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        setupSubscriptions()
        view.backgroundColor = .clear

        setExpanded(isExpanded)
    }

    private func setupSubscriptions() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                
                let targetItem = newState == .search ? self.pickerItems[0] : self.pickerItems[1]
                if self.pickerState?.selectedItem.text != targetItem.text {
                    // Disable animations when updating picker state
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.pickerState?.selectedItem = targetItem
                    }
                }
                
                self.updateLayouts()
            }
            .store(in: &cancellables)
    }

    private func updateLayouts() {
        self.view.layoutIfNeeded()
    }

    func focusTextField() {
        textEntryViewController.focusTextField()
    }

    func unfocusTextField() {
        textEntryViewController.unfocusTextField()
    }

    private func setupViews() {
        view.backgroundColor = UIColor.systemBackground

        let currentToggleState = switchBarHandler.currentToggleState
        let initialSelection = currentToggleState == .search ? pickerItems[0] : pickerItems[1]
        
        let state = PickerState(
            items: pickerItems,
            initialSelection: initialSelection,
            onSelectionChanged: { [weak self] selectedItem in
                self?.segmentedPickerSelectionChanged(selectedItem)
            }
        )
        pickerState = state
        
        let pickerWrapper = PickerWrapper(state: state)
        let hostingController = UIHostingController(rootView: pickerWrapper)
        segmentedPickerHostingController = hostingController
        hostingController.view.backgroundColor = UIColor.clear

        view.addSubview(backButton)
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        addChild(textEntryViewController)
        view.addSubview(textEntryViewController.view)
        textEntryViewController.didMove(toParent: self)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        textEntryViewController.view.translatesAutoresizingMaskIntoConstraints = false

        backButton.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
    }

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded

        segmentedControlTopConstraint?.isActive = isExpanded

        backButton.alpha = isExpanded ? 1 : 0
        segmentedPickerHostingController?.view.alpha = isExpanded ? 1 : 0

        textEntryViewController.setExpanded(isExpanded)
    }

    private func setupConstraints() {

        guard let segmentedPickerView = segmentedPickerHostingController?.view else { return }

        segmentedControlTopConstraint = segmentedPickerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)

        NSLayoutConstraint.activate([
            segmentedPickerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedPickerView.heightAnchor.constraint(equalToConstant: Constants.segmentedControlHeight),

            textEntryViewController.view.topAnchor.constraint(equalTo: segmentedPickerView.bottomAnchor, constant: Constants.textEntryViewTopPadding),
            textEntryViewController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.textEntryViewSidePadding),
            textEntryViewController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Constants.textEntryViewSidePadding),
            // Create bottom constraint with lower priority to avoid conflicts with parent constraints
            textEntryViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).withPriority(.init(999)),

            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.backButtonHorizontalPadding),
            backButton.centerYAnchor.constraint(equalTo: segmentedPickerView.centerYAnchor)
        ])
    }

    // MARK: - Actions
    private func segmentedPickerSelectionChanged(_ selectedItem: ImageSegmentedPickerItem) {
        let newMode: TextEntryMode = pickerItems.first == selectedItem ? .search : .aiChat
        switchBarHandler.setToggleState(newMode)
    }
}

private class PickerState: ObservableObject {
    @Published var selectedItem: ImageSegmentedPickerItem
    let items: [ImageSegmentedPickerItem]
    let onSelectionChanged: (ImageSegmentedPickerItem) -> Void

    init(items: [ImageSegmentedPickerItem], initialSelection: ImageSegmentedPickerItem, onSelectionChanged: @escaping (ImageSegmentedPickerItem) -> Void) {
        self.items = items
        self.selectedItem = initialSelection
        self.onSelectionChanged = onSelectionChanged
    }
}

private struct PickerWrapper: View {
    @ObservedObject var state: PickerState

    var body: some View {
        ImageSegmentedPickerView(
            items: state.items,
            selectedItem: $state.selectedItem,
        )
        .frame(width: 230)
        .onChange(of: state.selectedItem) { newItem in
            state.onSelectionChanged(newItem)
        }
    }
}
