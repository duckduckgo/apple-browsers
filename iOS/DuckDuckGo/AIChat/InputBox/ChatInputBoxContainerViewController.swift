//
//  ChatInputBoxContainerViewController.swift
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
import Combine

protocol ChatInputBoxContainerViewControllerDelegate: AnyObject {
    func chatInputBoxContainerViewControllerDidPressBack(_ viewController: ChatInputBoxContainerViewController)
    func chatInputBoxContainerViewController(_ viewController: ChatInputBoxContainerViewController, didSubmitQuery query: String)
    func chatInputBoxContainerViewController(_ viewController: ChatInputBoxContainerViewController, didSubmitPrompt prompt: String)
}

final class ChatInputBoxContainerViewController: UIViewController {
    private let chatInputBoxViewController: ChatInputBoxViewController
    private var cancellables = Set<AnyCancellable>()
    weak var delegate: ChatInputBoxContainerViewControllerDelegate?
    private let position: AddressBarPosition

    // MARK: - Initialization
    
    init(viewModel: AIChatInputBoxViewModel, position: AddressBarPosition = .top) {
        self.chatInputBoxViewController = ChatInputBoxViewController(viewModel: viewModel)
        self.position = position
        super.init(nibName: nil, bundle: nil)
        
        configureViewModel(viewModel)
        setupSubscriptions(for: viewModel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Private Methods
    
    private func configureViewModel(_ viewModel: AIChatInputBoxViewModel) {
        viewModel.focusState = .focused
        viewModel.inputMode = .search
    }
    
    private func setupSubscriptions(for viewModel: AIChatInputBoxViewModel) {
        viewModel.didPressBackButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.chatInputBoxContainerViewControllerDidPressBack(self)
            }
            .store(in: &cancellables)
            
        viewModel.didSubmitQuery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                self.delegate?.chatInputBoxContainerViewController(self, didSubmitQuery: query)
            }
            .store(in: &cancellables)
            
        viewModel.didSubmitPrompt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompt in
                guard let self = self else { return }
                self.delegate?.chatInputBoxContainerViewController(self, didSubmitPrompt: prompt)
            }
            .store(in: &cancellables)
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        setupChatInputBox()
    }
    
    private func setupChatInputBox() {
        addChild(chatInputBoxViewController)
        configureChatInputBoxView()
        setupChatInputBoxConstraints()
        chatInputBoxViewController.didMove(toParent: self)
    }
    
    private func configureChatInputBoxView() {
        chatInputBoxViewController.view.translatesAutoresizingMaskIntoConstraints = false
        chatInputBoxViewController.view.backgroundColor = .clear
        view.addSubview(chatInputBoxViewController.view)
    }
    
    private func setupChatInputBoxConstraints() {
        var constraints: [NSLayoutConstraint] = [
            chatInputBoxViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatInputBoxViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        
        switch position {
        case .top:
            constraints.append(contentsOf: [
                chatInputBoxViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                chatInputBoxViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
            ])
        case .bottom:
            constraints.append(chatInputBoxViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
