//
//  FaceBlurProcessor.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

struct FaceBlurProcessor: Sendable {
    private let ciContext = CIContext()

    func detectFaces(in image: UIImage, threshold: Double) throws -> [BlurTarget] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let normalizedThreshold = max(0, min(1, threshold))

        let filtered = normalizedThreshold <= 0
            ? observations
            : observations.filter { detectionScore(for: $0) >= normalizedThreshold }

        return filtered.map { observation in
            target(from: convert(observation.boundingBox, for: image))
        }
    }

    func render(image: UIImage, with targets: [BlurTarget], settings: BlurSettings) -> UIImage? {
        guard !targets.isEmpty else { return image }
        guard let blurredBase = image.applyingBlur(style: settings.style, intensity: settings.intensity, context: ciContext) else {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            for target in targets where target.isBlurred {
                let circleRect = target.circleRect(faceScale: settings.faceRadiusScale)
                let path = UIBezierPath(ovalIn: circleRect)
                context.cgContext.saveGState()
                context.cgContext.addPath(path.cgPath)
                context.cgContext.clip()
                blurredBase.draw(in: CGRect(origin: .zero, size: image.size))
                context.cgContext.restoreGState()
            }
        }
    }

    private func convert(_ boundingBox: CGRect, for image: UIImage) -> CGRect {
        let size = image.size
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        let x = boundingBox.minX * size.width
        let y = (1 - boundingBox.maxY) * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func target(from rect: CGRect) -> BlurTarget {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = max(rect.width, rect.height) * 0.6
        return BlurTarget(center: center, baseRadius: baseRadius, type: .face)
    }

    private func detectionScore(for observation: VNFaceObservation) -> Double {
        let confidence = Double(observation.confidence)
        let area = Double(observation.boundingBox.width * observation.boundingBox.height)
        let normalizedArea = min(1.0, sqrt(max(area, 0)) * 4)
        return min(1.0, confidence * 0.7 + normalizedArea * 0.3)
    }
}

private extension UIImage {
    func applyingBlur(style: BlurStyle, intensity: Double, context: CIContext) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let outputImage: CIImage?

        switch style {
        case .pixellate:
            let filter = CIFilter.pixellate()
            filter.inputImage = ciImage
            let scale = max(8, ciImage.extent.width * CGFloat(intensity) * 0.05)
            filter.scale = Float(scale)
            outputImage = filter.outputImage
        case .gaussian:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciImage
            let radius = max(2, ciImage.extent.width * CGFloat(intensity) * 0.02)
            filter.radius = Float(radius)
            outputImage = filter.outputImage
        }

        guard let finalImage = outputImage?.cropped(to: ciImage.extent) else { return nil }
        guard let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
