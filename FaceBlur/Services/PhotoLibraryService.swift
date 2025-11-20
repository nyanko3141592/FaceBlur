//
//  PhotoLibraryService.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

enum PhotoLibraryError: LocalizedError {
    case noImage
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "保存する画像が見つかりませんでした"
        case .authorizationDenied:
            return "写真ライブラリへのアクセスが拒否されました"
        }
    }
}

struct PhotoLibraryService {
    static func save(_ image: UIImage, metadata: [String: Any]?, options: ExportOptions) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw PhotoLibraryError.authorizationDenied
            }
        } else if !(status == .authorized || status == .limited) {
            throw PhotoLibraryError.authorizationDenied
        }

        guard let data = encode(image: image, metadata: options.removeMetadata ? nil : metadata) else {
            throw PhotoLibraryError.noImage
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private static func encode(image: UIImage, metadata: [String: Any]?) -> Data? {
        if metadata == nil {
            return image.jpegData(compressionQuality: 0.95)
        }

        guard let cgImage = image.cgImage else {
            return image.jpegData(compressionQuality: 0.95)
        }

        let data = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
