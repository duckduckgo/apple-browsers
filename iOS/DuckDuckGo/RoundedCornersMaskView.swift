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

final class RoundedCornersMaskView: UIView {

    // MARK: - Nested Types
    enum Corners {
        case top
        case bottom
        case all
    }

    // MARK: - Properties
    private let cornerRadius: CGFloat
    private let cornerColor: UIColor
    private let corners: Corners
    private var cornerViews: [UIView] = []

    // MARK: - Initialization
    init(cornerRadius: CGFloat, cornerColor: UIColor, corners: Corners = .top) {
        self.cornerRadius = cornerRadius
        self.cornerColor = cornerColor
        self.corners = corners
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        self.cornerRadius = 20
        self.cornerColor = .white
        self.corners = .top
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup
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
        let shouldCreateTopCorners = (corners == .top || corners == .all)
        let shouldCreateBottomCorners = (corners == .bottom || corners == .all)

        // Create top corners if needed
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

        // Create bottom corners if needed
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

        // Apply masks to corner views
        if corners == .top || corners == .all {
            if cornerViews.count >= 2 {
                applyTopLeftMask(to: cornerViews[0])
                applyTopRightMask(to: cornerViews[1])
            }
        }

        if corners == .bottom || corners == .all {
            let startIndex = (corners == .all) ? 2 : 0
            if cornerViews.count >= startIndex + 2 {
                applyBottomLeftMask(to: cornerViews[startIndex])
                applyBottomRightMask(to: cornerViews[startIndex + 1])
            }
        }
    }

    private func applyTopLeftMask(to view: UIView) {
        let maskLayer = CAShapeLayer()

        // Create a path for the entire rectangle
        let path = UIBezierPath(rect: view.bounds)

        // Create a path for the quarter circle to cut out
        let circlePath = UIBezierPath(arcCenter: CGPoint(x: cornerRadius, y: cornerRadius),
                                     radius: cornerRadius,
                                     startAngle: .pi,
                                     endAngle: .pi * 1.5,
                                     clockwise: true)
        circlePath.addLine(to: CGPoint(x: cornerRadius, y: cornerRadius))
        circlePath.close()

        // Append the circle path to cut it out from the rectangle
        path.append(circlePath)
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.mask = maskLayer
    }

    private func applyTopRightMask(to view: UIView) {
        let maskLayer = CAShapeLayer()

        // Create a path for the entire rectangle
        let path = UIBezierPath(rect: view.bounds)

        // Create a path for the quarter circle to cut out
        let circlePath = UIBezierPath(arcCenter: CGPoint(x: 0, y: cornerRadius),
                                     radius: cornerRadius,
                                     startAngle: .pi * 1.5,
                                     endAngle: .pi * 2,
                                     clockwise: true)
        circlePath.addLine(to: CGPoint(x: 0, y: cornerRadius))
        circlePath.close()

        // Append the circle path to cut it out from the rectangle
        path.append(circlePath)
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.mask = maskLayer
    }

    private func applyBottomLeftMask(to view: UIView) {
        let maskLayer = CAShapeLayer()

        // Create a path for the entire rectangle
        let path = UIBezierPath(rect: view.bounds)

        // Create a path for the quarter circle to cut out
        let circlePath = UIBezierPath(arcCenter: CGPoint(x: cornerRadius, y: 0),
                                     radius: cornerRadius,
                                     startAngle: .pi * 0.5,
                                     endAngle: .pi,
                                     clockwise: true)
        circlePath.addLine(to: CGPoint(x: cornerRadius, y: 0))
        circlePath.close()

        // Append the circle path to cut it out from the rectangle
        path.append(circlePath)
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.mask = maskLayer
    }

    private func applyBottomRightMask(to view: UIView) {
        let maskLayer = CAShapeLayer()

        // Create a path for the entire rectangle
        let path = UIBezierPath(rect: view.bounds)

        // Create a path for the quarter circle to cut out
        let circlePath = UIBezierPath(arcCenter: CGPoint(x: 0, y: 0),
                                     radius: cornerRadius,
                                     startAngle: 0,
                                     endAngle: .pi * 0.5,
                                     clockwise: true)
        circlePath.addLine(to: CGPoint(x: 0, y: 0))
        circlePath.close()

        // Append the circle path to cut it out from the rectangle
        path.append(circlePath)
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.mask = maskLayer
    }
}
