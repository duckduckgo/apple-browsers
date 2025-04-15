//
//  CompositeShadowView.swift
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

class CompositeShadowView: UIView {

    var shadows: [Shadow] = [] {
        didSet {
            setUpShadows()
        }
    }

    private var shadowViews: [UIView] = []

    init(shadows: [Shadow] = []) {
        super.init(frame: .zero)

        self.shadows = shadows

        setUpShadows()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override class var layerClass: AnyClass {
        return CustomLayer.self
    }

    private var customLayer: CustomLayer {
        // swiftlint:disable:next force_cast
        return layer as! CustomLayer
    }

    func updateShadow(_ shadow: Shadow) {
        guard let shadowView = shadowViews.first(where: { $0.layer.name == shadow.id }) else {
            return
        }

        shadowView.layer.applyShadowProperties(shadow)
    }

    private func setUpShadows() {

        shadowViews.forEach {
            customLayer.removeShadowLayer(layer: $0.layer)
            $0.removeFromSuperview()
        }
        shadowViews.removeAll()

        for shadow in shadows {
            let shadowView = UIView()
            shadowView.layer.name = shadow.id
            shadowView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shadowView.frame = bounds
            shadowView.backgroundColor = backgroundColor
            shadowView.layer.cornerRadius = layer.cornerRadius

            shadowView.layer.applyShadowProperties(shadow)

            insertSubview(shadowView, at: 0)
            shadowViews.append(shadowView)
            customLayer.addShadowLayer(layer: shadowView.layer)
        }
    }

    struct Shadow {
        let id: String
        let color: UIColor
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize

        init(id: String = UUID().uuidString, color: UIColor, opacity: Float = 1.0, radius: CGFloat, offset: CGSize) {
            self.id = id
            self.color = color
            self.opacity = opacity
            self.radius = radius
            self.offset = offset
        }
    }

    private final class CustomLayer: CALayer {

        private var shadowLayers: [CALayer] = []

        func addShadowLayer(layer: CALayer) {
            guard sublayers?.contains(layer) == true else {
                assertionFailure("Attempting to add a shadow layer which is not in sublayers.")
                return
            }

            shadowLayers.append(layer)
        }

        func removeShadowLayer(layer: CALayer) {
            guard let index = shadowLayers.firstIndex(of: layer) else {
                return
            }
            
            shadowLayers.remove(at: index)
        }

        override var cornerRadius: CGFloat {
            didSet {
                // Iterate only through our own layers, otherwise we raise an exception.
                shadowLayers.forEach {
                    $0.cornerRadius = cornerRadius
                }
            }
        }

        override var backgroundColor: CGColor? {
            didSet {
                // Iterate only through our own layers, otherwise we raise an exception.
                shadowLayers.forEach {
                    $0.backgroundColor = backgroundColor
                }
            }
        }
    }
}

private extension CALayer {
    func applyShadowProperties(_ shadow: CompositeShadowView.Shadow) {
        shadowColor = shadow.color.cgColor
        shadowOpacity = shadow.opacity
        shadowRadius = shadow.radius
        shadowOffset = shadow.offset
        cornerRadius = shadow.radius
    }
}
