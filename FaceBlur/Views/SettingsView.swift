//
//  SettingsView.swift
//  FaceBlur
//
//  Created by 高橋直希 on 2025/11/20.
//

import SwiftUI

struct SettingsView: View {
    @Binding var settings: BlurSettings
    @Binding var exportOptions: ExportOptions

    var body: some View {
        Form {
            Section {
                Picker("ぼかしの種類", selection: $settings.style) {
                    ForEach(BlurStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("ぼかし設定")
            } footer: {
                Text("モザイクは四角いピクセル、ガウスは自然なぼかしです")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ぼかしの強さ")
                        Spacer()
                        Text(intensityLabel)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Slider(value: $settings.intensity, in: 0.2...1.0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("顔の範囲")
                        Spacer()
                        Text(radiusLabel)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Slider(value: $settings.faceRadiusScale, in: 0.5...2.0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("顔検知のしきい値")
                        Spacer()
                        Text(detectionLabel)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Slider(value: $settings.faceDetectionThreshold, in: 0...0.8)
                }
            } footer: {
                Text("しきい値を下げるほど緩く検出し、上げるほど厳密になります")
                    .font(.caption)
            }

            Section {
                Toggle("位置情報を削除", isOn: $exportOptions.removeMetadata)
            } header: {
                Text("プライバシー")
            } footer: {
                Text("保存時にGPS情報などのメタデータを削除します")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Color.accentColor)
                        Text("FaceBlur")
                            .font(.headline)
                    }
                    Text("すべての処理はこの端末内で完結します。写真がサーバーに送信されることはありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("アプリについて")
            }
        }
        .navigationTitle("設定")
    }

    private var intensityLabel: String {
        switch settings.intensity {
        case ..<0.4: return "弱"
        case ..<0.7: return "中"
        default: return "強"
        }
    }

    private var radiusLabel: String {
        switch settings.faceRadiusScale {
        case ..<0.75: return "小"
        case ..<1.25: return "中"
        default: return "大"
        }
    }

    private var detectionLabel: String {
        switch settings.faceDetectionThreshold {
        case ..<0.15: return "緩め"
        case ..<0.4: return "標準"
        default: return "厳しめ"
        }
    }
}
