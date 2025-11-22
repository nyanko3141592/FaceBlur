# FaceBlur SNS Guard

FaceBlur SNS Guard は、SNS に写真を投稿する前に顔を自動で検出・ぼかし、必要な部分だけを安全に開示できる iOS 17 以降向けの SwiftUI アプリです。アプリ本体からの写真選択や共有拡張での起動に備え、オンデバイス処理のみで Vision／Core Image を使ってプライバシーを守ります。

## 要件

- **ターゲット OS**: iOS 17 以上（iPhone 推奨）
- **開発環境**: Xcode 16 以降（Vision / CoreImage / PhotosUI / SwiftUI を利用）
- **依存ライブラリ**: Apple 純正フレームワークのみ

## ビルド & 実行

1. `FaceBlur.xcodeproj` を Xcode で開き、`FaceBlur` ターゲットを選択します。
2. Development Team を自身のアカウントに変更（`Signing & Capabilities`）。
3. 実機または iOS 17 以上のシミュレータを選択し、`⌘R` で実行。
4. 初回起動時に「写真」アクセス許可を求められるので許可してください（保存時には追加で `PHPhotoLibrary add-only` 権限を要求）。

## 主要画面フロー

| 画面 | 主な役割 |
| --- | --- |
| ホーム | PhotosPicker で 1〜5 枚の画像を選択。処理中はインジケータ表示。設定画面への導線あり。|
| 編集 | ページングで写真を切り替え。自動で全顔を円形ぼかしし、タップで個別トグル。ピンチズーム／ドラッグ対応。|
| 手動追加モード | 「ぼかしを追加」ボタンでアクティブ化。プレビュー上をタップするとその座標に円形モザイクを追加、即座にサイズ調整 UI が出現。|
| 設定 | ぼかし種類（モザイク／ガウス）、ぼかし強さ（強度）、顔ぼかしサイズ倍率、位置情報削除の ON/OFF を管理。|

## 機能詳細

### 自動顔検出とぼかし

- `PhotosPicker` で取得した `UIImage` を Vision (`VNDetectFaceRectanglesRequest`) に渡し、検出結果をアプリ独自の `BlurTarget` モデルに変換。
- `BlurTarget` は中心座標と基準半径を保持し、タイプ（face / manual）を持つため、処理側は一元的に扱えます。
- デフォルトではすべての検出済み顔に円形のぼかしを適用。`BlurSettings.faceRadiusScale` を変更すると顔タイプのみ半径が増減します。

### 手動ぼかしポイント

1. 編集画面下部で「ぼかしを追加」をタップすると追加モードへ。
2. プレビュー上をタップするとその位置に円形ぼかしを追加し、カード UI が表示されます。
3. カード内のスライダーで該当スポットの半径を個別に調整（画像サイズに応じて 3%〜25% の範囲）。
4. 追加済みのスポットを長押し、または追加モード中にタップすると選択状態になり、カードで再編集が可能。

### ズーム・パン操作

- プレビュー部分は `MagnificationGesture` + `DragGesture` の組み合わせで、最大 4x まで拡大可能。
- 拡大時のみパンが有効になり、画像外にはみ出し過ぎないようオフセットを制限しています。

### 保存・共有

- 「共有」: 現在の画像（ぼかし後）を `UIActivityViewController` に渡して SNS / メッセンジャーへ送信。
- 「保存」: `PhotoLibraryService` が JPEG へ書き出し、必要に応じて EXIF/位置情報を除去して `PHPhotoLibrary` に保存。

## アーキテクチャ概要

```
FaceBlurApp
└── ContentView (NavigationStack)
    └── HomeView
        ├── PhotosPicker
        ├── SettingsView
        └── NavigationDestination → EditorView
            ├── EditorCarousel / EditorPhotoPage / ImagePreviewView
            ├── EditorControls + ManualRadiusCard
            └── ShareSheet

Models/
├── BlurTarget / EditablePhoto / BlurSettings / ExportOptions
Services/
├── FaceBlurProcessor (Vision + CoreImage)
└── PhotoLibraryService (PHPhotoLibrary 保存)
ViewModels/
└── FaceBlurViewModel (状態管理・顔検出・レンダリング)
```

### データフロー

1. **選択**: `HomeView` が `PhotosPickerItem` を `FaceBlurViewModel` に渡す。
2. **検出 & レンダリング**: ViewModel の `loadPhotos` が Vision 検出 → `BlurTarget` 作成 → `FaceBlurProcessor.render` でぼかし済み画像を生成。
3. **編集**: `EditorView` でターゲットの ON/OFF、手動追加、個別半径変更を行い、必要に応じて再レンダリング。
4. **出力**: 保存 / 共有操作を行うと ViewModel が `PhotoLibraryService` または `ShareSheet` を呼び出す。

## ファイル別メモ

- `FaceBlur/FaceBlur/Models/FaceModels.swift`: すべての表現形（顔・手動）を `BlurTarget` に統合。`BlurSettings.faceRadiusScale` は顔にのみ効くよう変更済み。
- `FaceBlur/FaceBlur/ViewModels/FaceBlurViewModel.swift`: 手動ターゲットの追加・半径管理 API と、設定変更時の一括再レンダリングロジックを実装。
- `FaceBlur/FaceBlur/Views/EditorView.swift`: ページング UI、ズーム対応プレビュー、手動スポットカード、設定ボタン群など UI の要。
- `FaceBlur/FaceBlur/Services/FaceBlurProcessor.swift`: Vision → Core Image のパイプライン。円形マスクで描画し、顔タイプには倍率を適用。
- `FaceBlur/FaceBlur/Services/PhotoLibraryService.swift`: 写真保存処理およびメタデータ削除オプション。

## 今後の拡張アイデア

- 手動ターゲットの削除／複製 UI、ショートカット。
- Share Extension の実装（コンセプトに記載の共有シート対応）。
- 追加のぼかし種類（例: カスタムシェーダによる楕円、モーションぼかし）。
- ユーザー設定の永続化（`AppStorage` など）。
- 複数画像のワークフロー強化（サムネイル、進捗バー）。

## 参考

- 仕様書: `concept.md`
- 実装言語: Swift 5.10 / SwiftUI / Vision / CoreImage / PhotosUI

ドキュメント内の情報を参照しながら、アプリの挙動とコードの責務を把握してみてください。必要があれば追加セクション（テスト指針、Share Extension 設計など）をこのファイルに追記しても構いません。
