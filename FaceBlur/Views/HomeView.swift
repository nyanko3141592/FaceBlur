//
//  HomeView.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import PhotosUI
import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: FaceBlurViewModel
    @State private var navigateToEditor = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)

                Text("FaceBlur")
                    .font(.largeTitle.bold())

                Text("写真の顔を自動でぼかして\nプライバシーを守ります")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)

            PhotosPicker(selection: $viewModel.selectedPickerItems,
                         maxSelectionCount: viewModel.maxSelectionCount,
                         matching: .images) {
                Label("写真を選択", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            if viewModel.isProcessing {
                ProgressView("顔を検出中...")
                    .padding(.top, 24)
            }

            Spacer()
            Spacer()
        }
        .padding()
        .onChange(of: viewModel.hasLoadedPhotos) { _, hasPhotos in
            navigateToEditor = hasPhotos
        }
        .onChange(of: navigateToEditor) { _, isPresented in
            if !isPresented {
                viewModel.resetSession()
            }
        }
        .navigationDestination(isPresented: $navigateToEditor) {
            EditorView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(settings: $viewModel.settings, exportOptions: $viewModel.exportOptions)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(viewModel.isProcessing)
            }
        }
    }
}

