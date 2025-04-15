//
//  ResizablePreviewView.swift
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

import SwiftUI

#if DEBUG

@available(macOS 12.0, *)
struct ResizablePreviewView<Content: View>: View {

    let maxSize: CGSize
    let minSize: CGSize
    let content: Content

    @State private var size: CGSize

    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero

    private var currentSize: CGSize {
        if isDragging {
            CGSize(width: min(maxSize.width, max(minSize.width, size.width + dragOffset.width)),
                height: min(maxSize.height, max(minSize.height, size.height + dragOffset.height)))
        } else {
            size
        }
    }

    init(maxSize: CGSize, minSize: CGSize, @ViewBuilder content: () -> Content) {
        self.maxSize = maxSize
        self.minSize = minSize
        self.size = maxSize
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .frame(width: currentSize.width, height: currentSize.height)
                .border(Color.black, width: 1)
            ResizeHandle()
                .offset(x: (currentSize.width - 24) / 2,
                        y: (currentSize.height - 24) / 2)
                .frame(width: 24, height: 24, alignment: .bottomTrailing)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = CGSize(
                                width: value.translation.width * 2,
                                height: value.translation.height * 2
                            )
                        }
                        .onEnded { _ in
                            isDragging = false
                            size = CGSize(
                                width: min(maxSize.width, max(minSize.width, size.width + dragOffset.width)),
                                height: min(maxSize.height, max(minSize.height, size.height + dragOffset.height))
                            )
                            dragOffset = .zero
                        }
                )
        }
        .frame(width: maxSize.width, height: maxSize.height)
    }
}

@available(macOS 12.0, *)
private struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12))
            .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            .foregroundStyle(Color(.white))
            .background(Color(.gray))
    }
}

#endif
