//
//  FaceModels.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import Foundation
import SwiftUI
import UIKit

struct BlurTarget: Identifiable, Hashable {
    enum TargetType {
        case face
        case manual
    }

    let id: UUID = UUID()
    var center: CGPoint
    var baseRadius: CGFloat
    var isBlurred: Bool = true
    let type: TargetType

    func effectiveRadius(faceScale: Double) -> CGFloat {
        switch type {
        case .face:
            return max(8, baseRadius * CGFloat(faceScale))
        case .manual:
            return max(8, baseRadius)
        }
    }

    func circleRect(faceScale: Double) -> CGRect {
        let radius = effectiveRadius(faceScale: faceScale)
        return CGRect(x: center.x - radius,
                      y: center.y - radius,
                      width: radius * 2,
                      height: radius * 2)
    }
}

struct EditablePhoto: Identifiable {
    let id: UUID = UUID()
    let originalImage: UIImage
    let originalMetadata: [String: Any]?
    var processedImage: UIImage?
    var targets: [BlurTarget]

    var imageSize: CGSize {
        originalImage.size
    }

    var displayImage: UIImage {
        processedImage ?? originalImage
    }
}

enum BlurStyle: String, CaseIterable, Identifiable {
    case pixellate
    case gaussian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pixellate:
            return "モザイク"
        case .gaussian:
            return "ぼかし"
        }
    }
}

struct BlurSettings: Equatable {
    var style: BlurStyle = .gaussian
    /// 0.0 ... 1.0 where 1.0 means strongest blur
    var intensity: Double = 0.7
    /// 0.5 ... 2.0 multiplier for auto-detected face blur radius
    var faceRadiusScale: Double = 1.0
    /// 0.0 ... 1.0 lower = looser detection, higher = stricter
    var faceDetectionThreshold: Double = 0.2

    static let `default` = BlurSettings()
}

struct ExportOptions {
    var removeMetadata: Bool = true
}

struct FaceBlurAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
