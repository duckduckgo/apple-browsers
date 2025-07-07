//
//  VoiceSearchViewController.swift
//  DuckDuckGo
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

import UIKit
import SwiftUI

protocol VoiceSearchViewControllerDelegate: AnyObject {
    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget)
}

class VoiceSearchViewController: UIViewController {
    weak var delegate: VoiceSearchViewControllerDelegate?
    private let speechRecognizer = SpeechRecognizer()
    private let preferredTarget: VoiceSearchTarget?
    
    private lazy var blurView: UIVisualEffectView = {
        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        return effectView
    }()

    init(preferredTarget: VoiceSearchTarget? = nil) {
        self.preferredTarget = preferredTarget
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blurView.topAnchor.constraint(equalTo: view.topAnchor)
        ])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(blurView)
        view.backgroundColor = .clear
        installSpeechView()
        setupConstraints()
    }
    
    private func installSpeechView() {
        let model = VoiceSearchFeedbackViewModel(speechRecognizer: speechRecognizer, aiChatSettings: AIChatSettings(), preferredTarget: preferredTarget)
        model.delegate = self
        let speechView = VoiceSearchFeedbackView(speechModel: model)
        let controller = UIHostingController(rootView: speechView)
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }
}

extension VoiceSearchViewController: VoiceSearchFeedbackViewModelDelegate {
    func voiceSearchFeedbackViewModel(_ model: VoiceSearchFeedbackViewModel, didFinishQuery query: String?, target: VoiceSearchTarget) {
        delegate?.voiceSearchViewController(self, didFinishQuery: query, target: target)
    }
}
