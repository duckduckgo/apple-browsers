//
//  AIChatOmnibarTextContainerViewController.swift
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

import Cocoa

final class AIChatOmnibarTextContainerViewController: NSViewController {

    private let backgroundView = MouseBlockingBackgroundView()
    private let containerView = NSView()
    private let testButton = NSButton()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    static func create() -> AIChatOmnibarTextContainerViewController {
        return AIChatOmnibarTextContainerViewController()
    }

    override func loadView() {
        view = MouseOverView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        #if DEBUG
        print("AIChatOmnibarTextContainerViewController: view frame = \(view.frame), bounds = \(view.bounds)")
        #endif
    }

    private func setupUI() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        let colorsProvider = NSApp.delegateTyped.themeManager.theme.colorsProvider
        backgroundView.layer?.backgroundColor = colorsProvider.suggestionsBackgroundColor.cgColor
        view.addSubview(backgroundView)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(containerView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.title = "Test"
        testButton.bezelStyle = .rounded
        testButton.contentTintColor = .blue
        testButton.target = self
        testButton.action = #selector(testButtonClicked)
        containerView.addSubview(testButton)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            containerView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: testButton.topAnchor, constant: -10),

            testButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            testButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            testButton.widthAnchor.constraint(equalToConstant: 100),
            testButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    func startEventMonitoring() {
        backgroundView.startListening()
    }
    
    func cleanup() {
        backgroundView.stopListening()
    }

    @objc private func testButtonClicked() {
        print("hello")
    }
}
