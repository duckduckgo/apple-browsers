//
//  File.swift
//  PreferencesUI-macOS
//
//  Created by Sabrina Tardio on 28/07/25.
//

import SwiftUI
import SwiftUIExtensions

public struct CloseButton: View {
    let icon: NSImage
    let size: CGFloat
    let backgroundColor: Color
    let backgroundColorOnHover: Color
    let action: () -> Void

    @State var isHovering = false

    public init(icon: NSImage, size: CGFloat, backgroundColor: Color = .clear, backgroundColorOnHover: Color? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.backgroundColor = backgroundColor
        self.backgroundColorOnHover = backgroundColorOnHover ?? Color(.hover)
        self.action = action
        self.isHovering = isHovering
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering ? backgroundColorOnHover : backgroundColor)
                    .frame(width: size, height: size)
                Image(nsImage: icon)
                    .foregroundColor(Color(.blackWhite80))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            self.isHovering = isHovering
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pointingHand.pop()
            }
        }
    }
}

