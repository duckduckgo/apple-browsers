//
//  URLDragPreviewProvider.swift
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

import AppKit

struct URLDragPreviewProvider {

    static private let faviconSize: CGFloat = 16
    static private let maxWidth: CGFloat = 400

    let text: String
    let favicon: NSImage?
    let backgroundColor: NSColor
    let textColor: NSColor
    let width: CGFloat?

    init(text: String, favicon: NSImage?, backgroundColor: NSColor = .blackWhite5, textColor: NSColor = .textColor, width: CGFloat? = nil) {
        self.text = text
        self.favicon = favicon
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.width = width
    }

    init(url: URL, favicon: NSImage?, backgroundColor: NSColor = .blackWhite5, textColor: NSColor = .textColor, width: CGFloat? = nil) {
        self.text = url.toString(decodePunycode: true, dropScheme: true, dropTrailingSlash: true)
        self.favicon = favicon
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.width = width
    }

    func createPreview() -> NSView {
        let container = ColorView(frame: .zero, backgroundColor: backgroundColor, cornerRadius: 4)
        container.translatesAutoresizingMaskIntoConstraints = false

        let faviconView = favicon.map { favicon in
            let faviconView = NSImageView()
            faviconView.translatesAutoresizingMaskIntoConstraints = false
            faviconView.imageScaling = .scaleProportionallyDown

            faviconView.image = favicon

            return faviconView
        }

        let textField = NSTextField(labelWithString: text)
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.textColor = textColor
        textField.lineBreakMode = .byTruncatingMiddle
        textField.maximumNumberOfLines = 1

        container.addSubview(textField)

        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: 28),
        ])
        if let width {
            container.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            container.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth).isActive = true
        }
        if let faviconView {
            container.addSubview(faviconView)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 8),

                faviconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                faviconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                faviconView.widthAnchor.constraint(equalToConstant: Self.faviconSize),
                faviconView.heightAnchor.constraint(equalToConstant: Self.faviconSize),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            ])
        }

        container.layoutSubtreeIfNeeded()

        return container
    }

}

extension NSDraggingSession {
    func setPreviewProvider(_ provider: URLDragPreviewProvider) {
        let dragView = provider.createPreview()
        let dragImage = dragView.imageRepresentation()

        self.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragItem, _, _ in
            dragItem.imageComponentsProvider = {
                let component = NSDraggingImageComponent(key: .label)
                component.contents = dragImage
                component.frame = NSRect(origin: .zero, size: dragImage.size)
                return [component]
            }
        }
    }
}

@available(macOS 14.0, *)
#Preview("Preview with favicon") {
    URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: .homeFavicon).createPreview()
}
@available(macOS 14.0, *)
#Preview("Preview without favicon") {
    URLDragPreviewProvider(url: URL(string: "https://duckduckgo.com")!, favicon: nil).createPreview()
}
@available(macOS 14.0, *)
#Preview("Preview with text") {
    URLDragPreviewProvider(text: "DuckDuckGo", favicon: .homeFavicon).createPreview()
}
