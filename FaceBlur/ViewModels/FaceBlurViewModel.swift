//
//  FaceBlurViewModel.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import Combine
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class FaceBlurViewModel: ObservableObject {
    @Published var selectedPickerItems: [PhotosPickerItem] = [] {
        didSet { loadPhotos(from: selectedPickerItems) }
    }

    @Published private(set) var photos: [EditablePhoto] = []
    @Published var currentIndex: Int = 0
    @Published var isProcessing: Bool = false
    @Published var alert: FaceBlurAlert?
    @Published var settings: BlurSettings = .default {
        didSet { handleSettingsChange(from: oldValue) }
    }
    @Published var exportOptions = ExportOptions()

    let maxSelectionCount: Int = 1

    private let processor = FaceBlurProcessor()

    var hasLoadedPhotos: Bool {
        !photos.isEmpty
    }

    func photo(at index: Int) -> EditablePhoto? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    func resetSession() {
        selectedPickerItems = []
        photos = []
        currentIndex = 0
        isProcessing = false
    }

    func toggleTarget(_ targetID: BlurTarget.ID, in photoID: EditablePhoto.ID) {
        guard let photoIndex = photos.firstIndex(where: { $0.id == photoID }) else { return }
        guard let targetIndex = photos[photoIndex].targets.firstIndex(where: { $0.id == targetID }) else { return }

        photos[photoIndex].targets[targetIndex].isBlurred.toggle()
        regenerateImage(at: photoIndex)
    }

    func setAllTargetsBlurred(_ isBlurred: Bool) {
        guard photos.indices.contains(currentIndex) else { return }
        photos[currentIndex].targets = photos[currentIndex].targets.map { target in
            var mutableTarget = target
            mutableTarget.isBlurred = isBlurred
            return mutableTarget
        }
        regenerateImage(at: currentIndex)
    }

    @discardableResult
    func addManualBlurPoint(at location: CGPoint) -> BlurTarget.ID? {
        guard photos.indices.contains(currentIndex) else { return nil }
        var photo = photos[currentIndex]
        let clampedPoint = clamp(location, within: photo.imageSize)
        let radius = manualBlurRadius(for: photo.imageSize)
        let target = BlurTarget(center: clampedPoint, baseRadius: radius, isBlurred: true, type: .manual)
        photo.targets.append(target)
        photos[currentIndex] = photo
        regenerateImage(at: currentIndex)
        return target.id
    }

    func manualTargetRadius(_ targetID: BlurTarget.ID) -> CGFloat? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex].targets.first(where: { $0.id == targetID && $0.type == .manual })?.baseRadius
    }

    func manualRadiusRange(for photo: EditablePhoto?) -> ClosedRange<CGFloat>? {
        guard let size = photo?.imageSize else { return nil }
        let minDimension = min(size.width, size.height)
        let minRadius = minDimension * 0.03
        let maxRadius = minDimension * 0.25
        return minRadius...maxRadius
    }

    func updateManualTargetRadius(targetID: BlurTarget.ID, to newValue: CGFloat) {
        guard photos.indices.contains(currentIndex) else { return }
        guard let range = manualRadiusRange(for: photos[currentIndex]) else { return }
        guard let idx = photos[currentIndex].targets.firstIndex(where: { $0.id == targetID && $0.type == .manual }) else { return }
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        photos[currentIndex].targets[idx].baseRadius = clamped
        regenerateImage(at: currentIndex)
    }

    func removeManualTarget(targetID: BlurTarget.ID) {
        guard photos.indices.contains(currentIndex) else { return }
        photos[currentIndex].targets.removeAll(where: { $0.id == targetID && $0.type == .manual })
        regenerateImage(at: currentIndex)
    }

    func saveCurrentImage() async {
        guard photos.indices.contains(currentIndex) else { return }
        let photo = photos[currentIndex]
        let imageToSave = photo.processedImage ?? photo.originalImage
        do {
            try await PhotoLibraryService.save(imageToSave,
                                               metadata: exportOptions.removeMetadata ? nil : photo.originalMetadata,
                                               options: exportOptions)
            alert = FaceBlurAlert(title: "保存完了", message: "写真ライブラリに保存しました")
        } catch {
            alert = FaceBlurAlert(title: "保存エラー", message: error.localizedDescription)
        }
    }

    func regenerateImage(at index: Int) {
        guard photos.indices.contains(index) else { return }
        let photosSnapshot = photos
        let settingsSnapshot = settings
        let processor = self.processor
        Task.detached(priority: .userInitiated) { [photosSnapshot, settingsSnapshot, processor, index] in
            var workingPhoto = photosSnapshot[index]
            let processed = processor.render(image: workingPhoto.originalImage,
                                             with: workingPhoto.targets,
                                             settings: settingsSnapshot)
            workingPhoto.processedImage = processed
            let updatedPhoto = workingPhoto
            await MainActor.run { [index, updatedPhoto, weak self] in
                guard let self, index < self.photos.count else { return }
                self.photos[index] = updatedPhoto
            }
        }
    }

    private func regenerateImagesForSettings() {
        guard !photos.isEmpty else { return }
        let photosSnapshot = photos
        let settingsSnapshot = settings
        let processor = self.processor
        Task.detached(priority: .userInitiated) { [processor, settingsSnapshot, photosSnapshot] in
            let updated = photosSnapshot.map { photo -> EditablePhoto in
                var mutable = photo
                mutable.processedImage = processor.render(image: photo.originalImage,
                                                          with: photo.targets,
                                                          settings: settingsSnapshot)
                return mutable
            }
            let updatedCopy = updated
            await MainActor.run { [updatedCopy, weak self] in
                guard let self else { return }
                guard updatedCopy.count == self.photos.count else {
                    self.photos = updatedCopy
                    return
                }
                self.photos = updatedCopy
            }
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isProcessing = true
        photos = []
        currentIndex = 0

        let settingsSnapshot = settings
        let processor = self.processor
        let pickerItems = items
        Task.detached(priority: .userInitiated) { [processor, settingsSnapshot, pickerItems] in
            var loaded: [EditablePhoto] = []
            for item in pickerItems {
                if let payload = try await FaceBlurViewModel.loadImage(from: item) {
                    let image = payload.image
                    let targets: [BlurTarget]
                    do {
                        let detected = try processor.detectFaces(in: image,
                                                                  threshold: settingsSnapshot.faceDetectionThreshold)
                        targets = detected
                    } catch {
                        targets = []
                    }
                    var photo = EditablePhoto(originalImage: image,
                                              originalMetadata: payload.metadata,
                                              processedImage: nil,
                                              targets: targets)
                    photo.processedImage = processor.render(image: photo.originalImage,
                                                            with: photo.targets,
                                                            settings: settingsSnapshot)
                    loaded.append(photo)
                }
            }

            let loadedCopy = loaded
            await MainActor.run { [loadedCopy, weak self] in
                guard let self else { return }
                self.photos = loadedCopy
                self.isProcessing = false
                if loadedCopy.isEmpty {
                    self.alert = FaceBlurAlert(title: "読み込みエラー", message: "写真を読み込めませんでした")
                } else if loadedCopy.contains(where: { $0.targets.isEmpty }) {
                    self.alert = FaceBlurAlert(title: "顔が見つかりません", message: "一部の写真では顔が検出されませんでした。必要なら手動でぼかしを追加してください。")
                }
            }
        }
    }

    nonisolated private static func loadImage(from item: PhotosPickerItem) async throws -> LoadedImage? {
        if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            return LoadedImage(image: image, metadata: metadata(from: data))
        }
        return nil
    }

    nonisolated private static func metadata(from data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return metadata
    }

    private func manualBlurRadius(for imageSize: CGSize) -> CGFloat {
        min(imageSize.width, imageSize.height) * 0.08
    }

    private func clamp(_ point: CGPoint, within size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, point.x), size.width),
                y: min(max(0, point.y), size.height))
    }

    private func handleSettingsChange(from oldValue: BlurSettings) {
        if oldValue.faceDetectionThreshold != settings.faceDetectionThreshold {
            regenerateDetections()
        } else {
            regenerateImagesForSettings()
        }
    }

    func requestFaceRedetection() {
        regenerateDetections()
    }

    private func regenerateDetections() {
        guard !photos.isEmpty else { return }
        let photosSnapshot = photos
        let settingsSnapshot = settings
        let processor = self.processor
        Task.detached(priority: .userInitiated) { [processor, settingsSnapshot, photosSnapshot] in
            var updated: [EditablePhoto] = []
            for var photo in photosSnapshot {
                let manualTargets = photo.targets.filter { $0.type == .manual }
                let previousFaceTargets = photo.targets.filter { $0.type == .face }
                let detectedFaces: [BlurTarget]
                do {
                    detectedFaces = try processor.detectFaces(in: photo.originalImage,
                                                              threshold: settingsSnapshot.faceDetectionThreshold)
                } catch {
                    detectedFaces = previousFaceTargets
                }
                let mergedFaces = mergeFaceTargets(newTargets: detectedFaces,
                                                   previousTargets: previousFaceTargets)
                photo.targets = mergedFaces + manualTargets
                photo.processedImage = processor.render(image: photo.originalImage,
                                                        with: photo.targets,
                                                        settings: settingsSnapshot)
                updated.append(photo)
            }
            let updatedCopy = updated
            await MainActor.run { [updatedCopy, weak self] in
                guard let self else { return }
                guard updatedCopy.count == self.photos.count else {
                    self.photos = updatedCopy
                    return
                }
                self.photos = updatedCopy
            }
        }
    }

}

private func mergeFaceTargets(newTargets: [BlurTarget],
                              previousTargets: [BlurTarget]) -> [BlurTarget] {
    guard !previousTargets.isEmpty else { return newTargets }

    func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return sqrt(dx * dx + dy * dy)
    }

    return newTargets.map { target in
        var updated = target
        if let match = previousTargets.min(by: { lhs, rhs in
            distance(lhs.center, target.center) < distance(rhs.center, target.center)
        }) {
            let delta = distance(match.center, target.center)
            let threshold = max(match.baseRadius, target.baseRadius) * 0.5
            if delta <= threshold {
                updated.isBlurred = match.isBlurred
            }
        }
        return updated
    }
}

private struct LoadedImage {
    let image: UIImage
    let metadata: [String: Any]?
}
