//
//  SwitchBarPlaygroundViewController.swift
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
import DesignResourcesKit

class SwitchBarPlaygroundViewController: UIViewController {
    private(set) lazy var mainView = SwitchBarView()

    override func loadView () {
        view = mainView
    }  

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

extension SwitchBarPlaygroundViewController: OmniBarTransitionProxy {

    var containerView: UIView {
        mainView.containerView
    }
}

protocol OmniBarTransitionProxy {
    var containerView: UIView { get }
}

class SwitchBarView: UIView {

    let textView: UITextView = {
        let textView = UITextView()
        textView.isScrollEnabled = false
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.textAlignment = .center
        textView.textContainerInset = .zero
        return textView
    }()

    private let activeOutlineView = UIView()
    let boundingContainerLayoutGuide = UILayoutGuide()
    let containerView = UIView()

    init() {
        super.init(frame: .zero)
        setUpSubviews()
        setUpConstraints()
        setUpProperties()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        addSubview(containerView)
        containerView.addSubview(textView)
        addSubview(activeOutlineView)

        addLayoutGuide(boundingContainerLayoutGuide)
    }

    private func setUpConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        activeOutlineView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            activeOutlineView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: -2),
            activeOutlineView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: 2),
            activeOutlineView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -2),
            activeOutlineView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 2),

            containerView.leadingAnchor.constraint(equalTo: boundingContainerLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: boundingContainerLayoutGuide.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: boundingContainerLayoutGuide.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: boundingContainerLayoutGuide.bottomAnchor)
        ])
    }

    private func setUpProperties() {
        backgroundColor = UIColor(designSystemColor: .background)

        containerView.backgroundColor = UIColor(designSystemColor: .urlBar)
        containerView.layer.cornerRadius = 16
        containerView.layer.cornerCurve = .continuous

        activeOutlineView.isUserInteractionEnabled = false
        activeOutlineView.layer.borderColor = UIColor(designSystemColor: .accent).cgColor
        activeOutlineView.layer.borderWidth = 2
        activeOutlineView.layer.cornerRadius = 18
        activeOutlineView.layer.cornerCurve = .continuous
        activeOutlineView.backgroundColor = .clear
    }
}
