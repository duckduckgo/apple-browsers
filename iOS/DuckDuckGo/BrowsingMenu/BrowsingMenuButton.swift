//
//  BrowsingMenuButton.swift
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

class BrowsingMenuButton: UIView {

    let image = UIImageView()
    let label = UILabel()
    let highlight = UIView()
    
    private var action: () -> Void = {}
    
    static func make() -> BrowsingMenuButton {
        return BrowsingMenuButton()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureAppearance() {
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)
        highlight.layer.cornerRadius = 6
        highlight.isHidden = true
    }

    func configure(with entry: BrowsingMenuEntry, willPerformAction: ((@escaping () -> Void) -> Void)?) {
        guard case .regular(let name, let accessibilityLabel, let image, _, _, _, _, _, let action) = entry else {
            fatalError("Regular entry not found")
        }

        self.configure(with: image, label: name, accessibilityLabel: accessibilityLabel) {
            if let willPerformAction = willPerformAction {
                willPerformAction {
                    action()
                }
            } else {
                action()
            }
        }
    }

    func configure(with icon: UIImage, label: String, accessibilityLabel: String?, action: @escaping () -> Void) {
        image.image = icon
        self.label.setAttributedTextString(label)
        self.accessibilityLabel = accessibilityLabel ?? label
        self.action = action
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        highlight.isHidden = false
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        highlight.isHidden = !bounds.contains(location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        guard let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        
        if bounds.contains(location) {
            action()
        }
        
        highlight.isHidden = true
    }

    override func accessibilityActivate() -> Bool {
        action()
        return true
    }

    private func setupViews() {
        backgroundColor = .systemBackground
        insetsLayoutMarginsFromSafeArea = false

        highlight.translatesAutoresizingMaskIntoConstraints = false
        highlight.backgroundColor = .systemBackground
        addSubview(highlight)

        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFit
        addSubview(image)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        label.minimumScaleFactor = 0.9
        label.adjustsFontSizeToFitWidth = true
        label.attributedText = Self.makeLabelTemplate()
        addSubview(label)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            trailingAnchor.constraint(equalTo: highlight.trailingAnchor, constant: 3),
            bottomAnchor.constraint(equalTo: highlight.bottomAnchor, constant: 3),

            image.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.widthAnchor.constraint(equalToConstant: 24),
            image.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: highlight.leadingAnchor, constant: 3),
            highlight.trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 3)
        ])
    }

    private static func makeLabelTemplate() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return NSAttributedString(string: " ",
                                  attributes: [.font: UIFont.systemFont(ofSize: 14),
                                               .paragraphStyle: paragraphStyle])
    }
}
