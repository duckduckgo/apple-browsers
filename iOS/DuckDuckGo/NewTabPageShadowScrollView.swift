//
//  NewTabPageShadowScrollView.swift
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

import SwiftUI
import UIKit
import DesignResourcesKit

struct NewTabPageShadowScrollView<Content: View>: UIViewRepresentable {
    var content: Content
    let shadowColor: UIColor
    let overflowOffset: CGFloat
    let setUpScrollView: (UIScrollView) -> Void

    init(shadowColor: Color,
         overflowOffset: CGFloat = 50,
         setUpScrollView: @escaping (UIScrollView) -> Void,
         @ViewBuilder content: () -> Content) {
        self.content = content()
        self.shadowColor = UIColor(shadowColor)
        self.overflowOffset = overflowOffset
        self.setUpScrollView = setUpScrollView
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator

        setUpScrollView(scrollView)

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hostingController.view)
        scrollView.clipsToBounds = false

        let hostingView = hostingController.view!

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        let topShadowView = makeShadowView(isTop: true)
        topShadowView.backgroundColor = .white
        topShadowView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.addSubview(topShadowView)

        let bottomShadowView = makeShadowView(isTop: false)
        bottomShadowView.backgroundColor = .white
        bottomShadowView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.addSubview(bottomShadowView)

        // Added to make shadows extend beyond scrollView horizontally (visible on landscape).
        let additionalOffset: CGFloat = 100

        NSLayoutConstraint.activate([
            topShadowView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: -additionalOffset),
            topShadowView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: additionalOffset),
            topShadowView.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            topShadowView.heightAnchor.constraint(equalToConstant: ShadowScrollViewMetrics.shadowViewHeight),

            bottomShadowView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: -additionalOffset),
            bottomShadowView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: additionalOffset),
            bottomShadowView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
            bottomShadowView.heightAnchor.constraint(equalToConstant: ShadowScrollViewMetrics.shadowViewHeight)
        ])

        context.coordinator.topShadowView = topShadowView
        context.coordinator.bottomShadowView = bottomShadowView

        context.coordinator.updateShadowVisibility(scrollView: scrollView)

        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        uiView.layoutIfNeeded()
        context.coordinator.updateShadowVisibility(scrollView: uiView)
    }

    private func makeShadowView(isTop: Bool) -> UIView {

        let offsetMultiplier: CGFloat = isTop ? 1 : -1

        let shadowView = CompositeShadowView(shadows: [
            .init(color: shadowColor,
                  radius: ShadowScrollViewMetrics.ShadowLayer1.radius,
                  offset: CGSize(width: 0, height: offsetMultiplier * ShadowScrollViewMetrics.ShadowLayer1.yOffset)),
            .init(color: shadowColor, radius: ShadowScrollViewMetrics.ShadowLayer2.radius,
                  offset: CGSize(width: 0, height: offsetMultiplier * ShadowScrollViewMetrics.ShadowLayer2.yOffset))
        ])

        return shadowView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: NewTabPageShadowScrollView
        var topShadowView: UIView?
        var bottomShadowView: UIView?
        
        init(_ parent: NewTabPageShadowScrollView) {
            self.parent = parent
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateShadowVisibility(scrollView: scrollView)
        }

        func updateShadowVisibility(scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            let overflowOffset = parent.overflowOffset

            let topProgress = (overflowOffset - offsetY) / overflowOffset
            topShadowView?.alpha = max(0, min(1.0, 1.0 - topProgress))

            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.bounds.height

            let bottomOverflow = offsetY + scrollViewHeight - contentHeight
            let bottomProgress = (bottomOverflow + overflowOffset) / overflowOffset
            let bottomOpacity = max(0, min(1.0, 1.0 - bottomProgress))

            bottomShadowView?.alpha = bottomOpacity
        }
    }
}

// Defined outside because generic type does not support static stored properties
private struct ShadowScrollViewMetrics {
    static let shadowViewHeight: CGFloat = 44

    struct ShadowLayer1 {
        static let radius: CGFloat = 12
        static let yOffset: CGFloat = 4
    }

    struct ShadowLayer2 {
        static let radius: CGFloat = 48
        static let yOffset: CGFloat = 16
    }
}
