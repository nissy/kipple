# TASKS

## macOS 26 Tahoe ガイドライン適合
- メニューバーの「Preferences…」表記を「Settings…」へ統一し、ローカライズも更新する（`Kipple/App/MenuBarApp.swift`）。
- 設定ウインドウをNSToolbarベースのタブレイアウトへ移行し、Liquid Glass推奨のアイコン付きセグメント構成に置き換える（`Kipple/Presentation/Features/Settings/Views/SettingsView.swift`）。
- 設定ウインドウのスタイルマスクから`.miniaturizable`を除外し、最小化ボタンを無効化する（`Kipple/Infrastructure/Managers/WindowManager.swift`）。
- ESCキーで設定ウインドウを閉じられるよう`cancelOperation(_:)`ハンドラを追加する（`SettingsView`またはホストNSWindow側）。
- 真偽値項目をトグルスイッチからチェックボックス（SwiftUIの`Toggle`に`.checkbox`スタイル）へ変更し、macOS設定ウインドウのコントロール指針に合わせる（`Kipple/Presentation/Features/Settings/Views/SettingsRow.swift`ほか）。
- Liquid Glassテーマ設定（背景ブラー、アクティブ/インアクティブ時の彩度変化）を適用し、Tahoeテーマ機能と整合するスタイルAPIを導入する（`SettingsView`および関連ビュー）。
