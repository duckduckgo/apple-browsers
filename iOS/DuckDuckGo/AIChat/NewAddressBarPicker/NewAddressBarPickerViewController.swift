//
//  NewAddressBarPickerViewController.swift
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
import AIChat
import Core

final class NewAddressBarPickerViewController: UIViewController {
    
    private let aiChatSettings: AIChatSettingsProvider
    
    init(aiChatSettings: AIChatSettingsProvider) {
        self.aiChatSettings = aiChatSettings
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var contentView: NewAddressBarPickerContentView!
    private var hostingController: UIHostingController<NewAddressBarPickerContentView>!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupContentView()
        DailyPixel.fireDailyAndCount(pixel: .aiChatNewAddressBarPickerDisplayed)
    }
    
    private func setupContentView() {
        contentView = NewAddressBarPickerContentView(
            aiChatSettings: aiChatSettings
        ) { [weak self] in
            self?.dismiss(animated: true)
        }
        
        hostingController = UIHostingController(rootView: contentView)
        hostingController.view.backgroundColor = .clear
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .portrait
        case .pad:
            return .all
        default:
            return .all
        }
    }
}
