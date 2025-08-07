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
        static let backButtonSize: CGFloat = 44
    }

    private var segmentedPickerHostingController: UIHostingController<PickerWrapper>?
    let textEntryViewController: SwitchBarTextEntryViewController
    let backButton = BrowserChromeButton()

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    var segmentedPickerView: UIView? { segmentedPickerHostingController?.viewIfLoaded }

    // Items for the segmented picker
    private let pickerItems = [
        ImageSegmentedPickerItem(
            text: UserText.searchInputToggleSearchButtonTitle,
            selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearchGradientColor),
            unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearch)
        ),
        ImageSegmentedPickerItem(
            text: UserText.searchInputToggleAIChatButtonTitle,
            selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChatGradientColor),
            unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChat)
        )
    ]
    
    private var pickerViewModel: ImageSegmentedPickerViewModel!

    // MARK: - Initialization
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        self.textEntryViewController = SwitchBarTextEntryViewController(handler: switchBarHandler)
        super.init(nibName: nil, bundle: nil)
        
        let currentToggleState = switchBarHandler.currentToggleState
        let initialSelection = currentToggleState == .search ? pickerItems[0] : pickerItems[1]
        
        self.pickerViewModel = ImageSegmentedPickerViewModel(
            items: pickerItems,
            selectedItem: initialSelection,
            configuration: ImageSegmentedPickerConfiguration(),
            scrollProgress: nil
        )
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
    }

    private func setupSubscriptions() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                
                let targetItem = newState == .search ? self.pickerItems[0] : self.pickerItems[1]
                if self.pickerViewModel.selectedItem.text != targetItem.text {
                    self.pickerViewModel.selectItem(targetItem)
                }
                
                self.updateLayouts()
            }
            .store(in: &cancellables)
        
        // Listen for picker selection changes to notify SwipeContainerManager
        pickerViewModel.$selectedItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedItem in
                guard let self = self else { return }
                self.segmentedPickerSelectionChanged(selectedItem)
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
        view.backgroundColor = .clear

        let pickerWrapper = PickerWrapper(
            viewModel: pickerViewModel
        )
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

    private func setupConstraints() {

        guard let segmentedPickerView = segmentedPickerHostingController?.view else { return }

        NSLayoutConstraint.activate([
            segmentedPickerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            segmentedPickerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedPickerView.heightAnchor.constraint(equalToConstant: Constants.segmentedControlHeight),

            textEntryViewController.view.topAnchor.constraint(equalTo: segmentedPickerView.bottomAnchor, constant: Constants.textEntryViewTopPadding),
            textEntryViewController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.textEntryViewSidePadding),
            textEntryViewController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Constants.textEntryViewSidePadding),
            textEntryViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.backButtonHorizontalPadding),
            backButton.centerYAnchor.constraint(equalTo: segmentedPickerView.centerYAnchor),
            backButton.heightAnchor.constraint(equalToConstant: Constants.backButtonSize),
            backButton.widthAnchor.constraint(equalToConstant: Constants.backButtonSize)
        ])
    }

    // MARK: - Actions
    private func segmentedPickerSelectionChanged(_ selectedItem: ImageSegmentedPickerItem) {
        let newMode: TextEntryMode = pickerItems.first == selectedItem ? .search : .aiChat
        switchBarHandler.setToggleState(newMode)
    }
    
    // MARK: - Scroll Progress
    func updateScrollProgress(_ progress: CGFloat) {
        pickerViewModel.updateScrollProgress(progress)
    }
}

private struct PickerWrapper: View {
    @ObservedObject var viewModel: ImageSegmentedPickerViewModel

    init(viewModel: ImageSegmentedPickerViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ImageSegmentedPickerView(viewModel: viewModel)
            .frame(width: 230)
    }
}
