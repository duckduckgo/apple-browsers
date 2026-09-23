//
//  RoundedCornersMaskView.swift
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

/**
 * RoundedCornerView
 *
 * A UIView subclass that applies quarter-circle cutout masks to specified corners.
 *
 * - Set `cornerRadius` to control the size of the cutouts
 * - Use `cornersPosition` (.top, .bottom, or .all) to specify which corners to mask
 * - Provide views in `cornerViews` array in order: top-left, top-right, bottom-left, bottom-right
 *
 */
final class RoundedCornersMaskView: UIView {

    enum CornersPosition {

        case top
        case bottom
        case all

    }

    private let cornerRadius: CGFloat
    private let cornerColor: UIColor
    private let cornersPosition: CornersPosition
    private var cornerViews: [UIView] = []

    init(cornerRadius: CGFloat, cornerColor: UIColor, cornersPosition: CornersPosition = .top) {
        self.cornerRadius = cornerRadius
        self.cornerColor = cornerColor
        self.cornersPosition = cornersPosition
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        self.cornerRadius = 20
        self.cornerColor = .white
        self.cornersPosition = .top
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        setupCornerViews()
    }

    private func setupCornerViews() {
        // Clear any existing corner views
        cornerViews.forEach { $0.removeFromSuperview() }
        cornerViews.removeAll()

        // Determine which corners to create
        let shouldCreateTopCorners = (cornersPosition == .top || cornersPosition == .all)
        let shouldCreateBottomCorners = (cornersPosition == .bottom || cornersPosition == .all)

        if shouldCreateTopCorners {
            let leftTopCorner = createCornerView()
            let rightTopCorner = createCornerView()

            NSLayoutConstraint.activate([
                leftTopCorner.topAnchor.constraint(equalTo: topAnchor),
                leftTopCorner.leadingAnchor.constraint(equalTo: leadingAnchor),
                leftTopCorner.widthAnchor.constraint(equalToConstant: cornerRadius),
                leftTopCorner.heightAnchor.constraint(equalToConstant: cornerRadius),

                rightTopCorner.topAnchor.constraint(equalTo: topAnchor),
                rightTopCorner.trailingAnchor.constraint(equalTo: trailingAnchor),
                rightTopCorner.widthAnchor.constraint(equalToConstant: cornerRadius),
                rightTopCorner.heightAnchor.constraint(equalToConstant: cornerRadius)
            ])

            cornerViews.append(contentsOf: [leftTopCorner, rightTopCorner])
        }

        if shouldCreateBottomCorners {
            let leftBottomCorner = createCornerView()
            let rightBottomCorner = createCornerView()

            NSLayoutConstraint.activate([
                leftBottomCorner.bottomAnchor.constraint(equalTo: bottomAnchor),
                leftBottomCorner.leadingAnchor.constraint(equalTo: leadingAnchor),
                leftBottomCorner.widthAnchor.constraint(equalToConstant: cornerRadius),
                leftBottomCorner.heightAnchor.constraint(equalToConstant: cornerRadius),

                rightBottomCorner.bottomAnchor.constraint(equalTo: bottomAnchor),
                rightBottomCorner.trailingAnchor.constraint(equalTo: trailingAnchor),
                rightBottomCorner.widthAnchor.constraint(equalToConstant: cornerRadius),
                rightBottomCorner.heightAnchor.constraint(equalToConstant: cornerRadius)
            ])

            cornerViews.append(contentsOf: [leftBottomCorner, rightBottomCorner])
        }
    }

    private func createCornerView() -> UIView {
        let view = UIView()
        view.backgroundColor = cornerColor
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var cornersToApply: [Corner] = []
        switch cornersPosition {
        case .top:
            cornersToApply = [.topLeft, .topRight]
        case .bottom:
            cornersToApply = [.bottomLeft, .bottomRight]
        case .all:
            cornersToApply = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }

        for (index, corner) in cornersToApply.enumerated() where index < cornerViews.count {
            applyCornerMask(to: cornerViews[index], corner: corner, cornerRadius: cornerRadius)
        }
    }

    private enum Corner {

        case topLeft, topRight, bottomLeft, bottomRight

        func arcCenter(radius: CGFloat) -> (x: CGFloat, y: CGFloat) {
            switch self {
            case .topLeft: return (radius, radius)
            case .topRight: return (0, radius)
            case .bottomLeft: return (radius, 0)
            case .bottomRight: return (0, 0)
            }
        }

        var angles: (start: CGFloat, end: CGFloat) {
            switch self {
            case .topLeft: return (.pi, .pi * 1.5)
            case .topRight: return (.pi * 1.5, .pi * 2)
            case .bottomLeft: return (.pi * 0.5, .pi)
            case .bottomRight: return (0, .pi * 0.5)
            }
        }

    }

    private func applyCornerMask(to view: UIView, corner: Corner, cornerRadius: CGFloat) {
        let maskLayer = CAShapeLayer()

        // Create a path for the entire rectangle
        let path = UIBezierPath(rect: view.bounds)

        // Get corner-specific parameters
        let center = corner.arcCenter(radius: cornerRadius)
        let angles = corner.angles

        // Create a path for the quarter circle to cut out
        let circlePath = UIBezierPath(
            arcCenter: CGPoint(x: center.x, y: center.y),
            radius: cornerRadius,
            startAngle: angles.start,
            endAngle: angles.end,
            clockwise: true
        )
        circlePath.addLine(to: CGPoint(x: center.x, y: center.y))
        circlePath.close()

        // Append the circle path to cut it out from the rectangle
        path.append(circlePath)
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.mask = maskLayer
    }

}
