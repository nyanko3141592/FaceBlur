//
//  ContentView.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/21.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FaceBlurViewModel()

    var body: some View {
        NavigationStack {
            HomeView(viewModel: viewModel)
                .navigationTitle("FaceBlur")
        }
    }
}

#Preview {
    ContentView()
}

