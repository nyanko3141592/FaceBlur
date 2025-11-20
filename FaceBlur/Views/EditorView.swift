//
//  EditorView.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import AVFoundation
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: FaceBlurViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var addingManualBlur = false
    @State private var selectedManualTargetID: BlurTarget.ID?

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.photos.isEmpty {
                emptyStateView
            } else {
                editorContent
            }
        }
        .padding([.horizontal, .bottom])
        .navigationTitle("編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("完了") {
                    dismiss()
                    viewModel.resetSession()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(settings: $viewModel.settings, exportOptions: $viewModel.exportOptions)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareImage = nil }) {
            if let shareImage {
                ShareSheet(items: [shareImage])
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: viewModel.currentIndex) { _ in
            selectedManualTargetID = nil
        }
        .onChange(of: viewModel.photos.map(\.id)) { _ in
            if let selectedManualTargetID,
               viewModel.manualTargetRadius(selectedManualTargetID) == nil {
                self.selectedManualTargetID = nil
            }
        }
        .onChange(of: viewModel.settings.faceDetectionThreshold) { _ in
            viewModel.requestFaceRedetection()
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "写真がまだありません",
            systemImage: "photo",
            description: Text("ホームに戻って写真を選んでください")
        )
    }

    private var editorContent: some View {
        VStack(spacing: 16) {
            carouselView
            statusInfoView
            controlsView
            manualRadiusCardView
        }
    }

    private var carouselView: some View {
        EditorCarousel(photos: viewModel.photos,
                        currentIndex: $viewModel.currentIndex,
                        faceRadiusScale: viewModel.settings.faceRadiusScale,
                        isAddingManualBlur: addingManualBlur,
                        selectedManualTargetID: selectedManualTargetID,
                        onToggleTarget: { photoID, target in
                            viewModel.toggleTarget(target.id, in: photoID)
                        },
                        onManualPoint: { point in
                            if let id = viewModel.addManualBlurPoint(at: point) {
                                selectedManualTargetID = id
                            }
                        },
                        onManualTargetSelect: { selectedManualTargetID = $0 })
    }

    private var controlsView: some View {
        EditorControls(viewModel: viewModel,
                        addingManualBlur: $addingManualBlur,
                        onShare: prepareShare,
                        onSave: {
            Task { await viewModel.saveCurrentImage() }
        })
    }

    @ViewBuilder
    private var manualRadiusCardView: some View {
        if let components = manualSliderComponents(), let targetID = selectedManualTargetID {
            ManualRadiusCard(value: components.binding,
                             range: components.range,
                             onDelete: {
                viewModel.removeManualTarget(targetID: targetID)
                selectedManualTargetID = nil
            },
                             onClearSelection: { selectedManualTargetID = nil })
                .transition(.opacity)
        }
    }

    private var statusInfoView: some View {
        VStack(spacing: 8) {
            if let current = viewModel.photo(at: viewModel.currentIndex) {
                let activeCount = current.targets.filter { $0.isBlurred }.count
                if viewModel.photos.count > 1 {
                    Text("\(viewModel.currentIndex + 1) / \(viewModel.photos.count)  ・  ぼかし \(activeCount) 箇所")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("ぼかし \(activeCount) 箇所")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if addingManualBlur {
                Text("ぼかしたい場所をタップ")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func prepareShare() {
        guard let current = viewModel.photo(at: viewModel.currentIndex) else { return }
        shareImage = current.processedImage ?? current.originalImage
        showShareSheet = shareImage != nil
    }

    private func manualSliderComponents() -> (binding: Binding<Double>, range: ClosedRange<Double>)? {
        guard let selectedManualTargetID,
              let photo = viewModel.photo(at: viewModel.currentIndex),
              let rawRange = viewModel.manualRadiusRange(for: photo) else {
            return nil
        }

        let sliderRange = Double(rawRange.lowerBound)...Double(rawRange.upperBound)
        let binding = Binding<Double>(
            get: {
                let current = viewModel.manualTargetRadius(selectedManualTargetID) ?? rawRange.lowerBound
                return Double(current)
            },
            set: { newValue in
                viewModel.updateManualTargetRadius(targetID: selectedManualTargetID,
                                                   to: CGFloat(newValue))
            }
        )
        return (binding: binding, range: sliderRange)
    }
}

private struct EditorControls: View {
    @ObservedObject var viewModel: FaceBlurViewModel
    @Binding var addingManualBlur: Bool
    let onShare: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // メイン操作ボタン
            HStack(spacing: 12) {
                Button(action: onShare) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onSave) {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            // 編集操作
            HStack(spacing: 12) {
                Button(action: { addingManualBlur.toggle() }) {
                    Label("追加", systemImage: addingManualBlur ? "checkmark.circle.fill" : "plus.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(addingManualBlur ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                        .foregroundStyle(addingManualBlur ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: { viewModel.setAllTargetsBlurred(true) }) {
                    Label("全員隠す", systemImage: "eye.slash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: { viewModel.setAllTargetsBlurred(false) }) {
                    Label("全員表示", systemImage: "eye")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct EditorCarousel: View {
    let photos: [EditablePhoto]
    @Binding var currentIndex: Int
    let faceRadiusScale: Double
    let isAddingManualBlur: Bool
    let selectedManualTargetID: BlurTarget.ID?
    let onToggleTarget: (EditablePhoto.ID, BlurTarget) -> Void
    let onManualPoint: (CGPoint) -> Void
    let onManualTargetSelect: (BlurTarget.ID) -> Void

    var body: some View {
        if photos.count == 1, let photo = photos.first {
            // 1枚の場合はTabViewを使わず直接表示
            EditorPhotoPage(
                photo: photo,
                faceRadiusScale: faceRadiusScale,
                isAddingManualBlur: isAddingManualBlur,
                selectedManualTargetID: selectedManualTargetID,
                onTargetTap: { onToggleTarget(photo.id, $0) },
                onManualPoint: onManualPoint,
                onManualTargetSelect: onManualTargetSelect
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
        } else {
            // 複数枚の場合はTabViewを使用
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    EditorPhotoPage(
                        photo: photo,
                        faceRadiusScale: faceRadiusScale,
                        isAddingManualBlur: isAddingManualBlur,
                        selectedManualTargetID: selectedManualTargetID,
                        onTargetTap: { onToggleTarget(photo.id, $0) },
                        onManualPoint: onManualPoint,
                        onManualTargetSelect: onManualTargetSelect
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }
}

private struct EditorPhotoPage: View {
    let photo: EditablePhoto
    let faceRadiusScale: Double
    let isAddingManualBlur: Bool
    let selectedManualTargetID: BlurTarget.ID?
    let onTargetTap: (BlurTarget) -> Void
    let onManualPoint: (CGPoint) -> Void
    let onManualTargetSelect: (BlurTarget.ID) -> Void

    var body: some View {
        ImagePreviewView(photo: photo,
                         faceRadiusScale: faceRadiusScale,
                         isAddingManualBlur: isAddingManualBlur,
                         selectedManualTargetID: selectedManualTargetID,
                         onTargetTap: onTargetTap,
                         onManualPoint: onManualPoint,
                         onManualTargetSelect: onManualTargetSelect)
    }
}

private struct ImagePreviewView: View {
    let photo: EditablePhoto
    let faceRadiusScale: Double
    let isAddingManualBlur: Bool
    let selectedManualTargetID: BlurTarget.ID?
    let onTargetTap: (BlurTarget) -> Void
    let onManualPoint: (CGPoint) -> Void
    let onManualTargetSelect: (BlurTarget.ID) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let containerRect = CGRect(origin: .zero, size: proxy.size)
            let baseImageRect = AVMakeRect(aspectRatio: photo.imageSize, insideRect: containerRect)
            let displayRect = currentDisplayRect(baseRect: baseImageRect, containerRect: containerRect)

            ZStack(alignment: .topLeading) {
                Image(uiImage: photo.displayImage)
                    .resizable()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)

                ForEach(photo.targets) { target in
                    if let circle = circle(for: target, in: displayRect) {
                        let isSelected = target.id == selectedManualTargetID
                        Circle()
                            .stroke(borderColor(for: target, isSelected: isSelected), lineWidth: isSelected ? 3 : 2)
                            .background(
                                Circle()
                                    .fill(target.isBlurred ? Color.clear : Color.green.opacity(0.35))
                            )
                            .frame(width: circle.diameter, height: circle.diameter)
                            .position(circle.center)
                            .contentShape(Circle())
                            .onLongPressGesture(minimumDuration: 0.25) {
                                if target.type == .manual {
                                    onManualTargetSelect(target.id)
                                }
                            }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .gesture(magnificationGesture())
            .simultaneousGesture(panGesture(containerRect: containerRect, baseRect: baseImageRect))
            .overlay(interactionOverlay(displayRect: displayRect), alignment: .topLeading)
        }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = min(max(1.0, lastZoomScale * value), 4.0)
                zoomScale = newScale
                if zoomScale == 1.0 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
            }
    }

    private func panGesture(containerRect: CGRect, baseRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1 else { return }
                let proposed = CGSize(width: lastOffset.width + value.translation.width,
                                      height: lastOffset.height + value.translation.height)
                offset = clampedOffset(proposed, containerRect: containerRect, baseRect: baseRect)
            }
            .onEnded { _ in
                guard zoomScale > 1 else { return }
                lastOffset = offset
            }
    }

    private func interactionOverlay(displayRect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleTap(at: value.location, displayRect: displayRect)
                    }
            )
    }

    private func handleTap(at location: CGPoint, displayRect: CGRect) {
        if isAddingManualBlur {
            if let manualTarget = hitTestTarget(at: location, displayRect: displayRect, restrictingTo: .manual) {
                onManualTargetSelect(manualTarget.id)
            } else if let imagePoint = convertToImagePoint(location, displayRect: displayRect) {
                onManualPoint(imagePoint)
            }
        } else if let target = hitTestTarget(at: location, displayRect: displayRect) {
            onTargetTap(target)
        }
    }

    private func hitTestTarget(at location: CGPoint,
                               displayRect: CGRect,
                               restrictingTo type: BlurTarget.TargetType? = nil) -> BlurTarget? {
        guard let imagePoint = convertToImagePoint(location, displayRect: displayRect) else { return nil }
        var bestMatch: (target: BlurTarget, distance: CGFloat)?

        for target in photo.targets {
            if let type, target.type != type { continue }
            let radius = target.effectiveRadius(faceScale: faceRadiusScale)
            let distance = hypot(imagePoint.x - target.center.x,
                                 imagePoint.y - target.center.y)
            guard distance <= radius else { continue }

            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (target, distance)
            }
        }

        return bestMatch?.target
    }

    private func currentDisplayRect(baseRect: CGRect, containerRect: CGRect) -> CGRect {
        let scaledSize = CGSize(width: baseRect.width * zoomScale, height: baseRect.height * zoomScale)
        let containerCenter = CGPoint(x: containerRect.midX, y: containerRect.midY)
        let origin = CGPoint(x: containerCenter.x - scaledSize.width / 2 + offset.width,
                             y: containerCenter.y - scaledSize.height / 2 + offset.height)
        return CGRect(origin: origin, size: scaledSize)
    }

    private func clampedOffset(_ offset: CGSize, containerRect: CGRect, baseRect: CGRect) -> CGSize {
        let scaledWidth = baseRect.width * zoomScale
        let scaledHeight = baseRect.height * zoomScale
        let horizontalLimit = max(0, (scaledWidth - containerRect.width) / 2)
        let verticalLimit = max(0, (scaledHeight - containerRect.height) / 2)
        let clampedX = min(max(offset.width, -horizontalLimit - 40), horizontalLimit + 40)
        let clampedY = min(max(offset.height, -verticalLimit - 40), verticalLimit + 40)
        return CGSize(width: clampedX, height: clampedY)
    }

    private func circle(for target: BlurTarget, in displayRect: CGRect) -> (center: CGPoint, diameter: CGFloat)? {
        let scaleFactor = displayRect.width / photo.imageSize.width
        guard scaleFactor.isFinite else { return nil }
        let centerX = displayRect.minX + (target.center.x / photo.imageSize.width) * displayRect.width
        let centerY = displayRect.minY + (target.center.y / photo.imageSize.height) * displayRect.height
        let radius = target.effectiveRadius(faceScale: faceRadiusScale) * scaleFactor
        return (CGPoint(x: centerX, y: centerY), radius * 2)
    }

    private func convertToImagePoint(_ point: CGPoint, displayRect: CGRect) -> CGPoint? {
        guard displayRect.contains(point) else { return nil }
        let relativeX = (point.x - displayRect.minX) / displayRect.width
        let relativeY = (point.y - displayRect.minY) / displayRect.height
        let x = relativeX * photo.imageSize.width
        let y = relativeY * photo.imageSize.height
        return CGPoint(x: x, y: y)
    }

    private func borderColor(for target: BlurTarget, isSelected: Bool) -> Color {
        if isSelected {
            return .yellow
        }
        if target.isBlurred {
            return target.type == .face ? Color.white.opacity(0.9) : Color.blue.opacity(0.9)
        } else {
            return Color.green
        }
    }
}

private struct ManualRadiusCard: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let onDelete: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("手動ぼかしサイズ")
                    .font(.headline)
                Spacer()
                Text(readableSize)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onDelete) {
                    Label("削除", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button(action: onClearSelection) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Slider(value: value, in: range)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var readableSize: String {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return "--" }
        let progress = (value.wrappedValue - range.lowerBound) / span
        switch progress {
        case ..<0.33: return "小"
        case ..<0.66: return "中"
        default: return "大"
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .background(configuration.isPressed ? Color.accentColor.opacity(0.7) : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
