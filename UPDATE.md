# Kipple - 最新API移行ガイド（AI一括実装版）

調査日: 2025年9月20日
対象環境: macOS Tahoe 26.0, Xcode 26.0, Swift 6.2

## 🎯 移行方針

**AIによる一括書き換えで、既存実装を最新APIで完全に置き換える**

### 基本戦略
1. 既存実装を最新APIへ段階的に直接書き換える
2. 各コンポーネント更新ごとにテストと動作確認を実施
3. 移行完了後に残存する互換コード・設定を整理して一本化

## 📋 現在の主要機能（移行時に維持すべき）

### ClipboardService
- **ポーリング**: 0.5-1.0秒の動的間隔調整
- **重複検出**: 最新50件のハッシュセット管理
- **内部コピー判定**: isInternalCopy/isFromEditorフラグ
- **アプリ監視**: アクティブアプリ情報の取得
- **自動クリア**: タイマーによる履歴自動削除

#### 現行コードで確認したポイント
- `ClipboardService`は`Timer`＋専用スレッド＋`NSLock`で状態管理しており、Actor化の際は`serialQueue`をどう移行するか検討が必要（`Kipple/Domain/Services/ClipboardService.swift`）。
- 履歴更新は`saveSubject`（Combine）経由でCore Dataへデバウンス保存しているため、Swift Concurrencyへ移行する際は`flushPendingSaves()`との互換性を維持する必要がある（同ファイルおよび`ClipboardServiceHistory.swift`）。
- アプリ終了処理では`MenuBarApp`が`Task`から`flushPendingSaves()`を呼び出している。Async APIへ移行する際はメニューバーや終了処理側の呼び出しパスも更新対象になる（`Kipple/App/MenuBarApp.swift`）。

### Core Data
- **WALチェックポイント**: SQLite最適化
- **バッチ削除**: 効率的な大量データ削除
- **バックグラウンド保存**: 非同期データ永続化

### UI/ViewModel
- **@Published**: リアルタイムUI更新
- **Combineデバウンス**: エディタテキストの遅延保存
- **UserDefaults監視**: 設定変更の即座反映

#### 現行コードで確認したポイント
- `MainViewModel`は`ClipboardService`の`@Published`プロパティを直接購読し、履歴フィルタを同期的に行っている。Async/await化すると`Task`ベースのポーリングやObservationマクロへの移行が必要（`Kipple/Presentation/Features/Main/ViewModels/MainViewModel.swift`）。
- `DataSettingsView`やメニューバーはサービスAPIを同期で呼び出しており、非同期化するとボタンアクションを`Task { await … }`へ置き換える必要がある（`Kipple/Presentation/Features/Settings/Views/DataSettingsView.swift`など）。
- Hotkey設定UIはCarbonベースの`HotkeyManager`と密結合している。`KeyboardShortcuts`へ移行する場合はSwiftUIビュー層のレコーダー（`HotkeyRecorderView`）との整合性を確認する必要がある。

## 🚀 新規実装の技術スタック

### 1. ClipboardService → Actor + Swift Concurrency

```swift
// NewClipboardService.swift
import Foundation
import AppKit

// プロトコルをasync/await対応に更新
protocol ModernClipboardServiceProtocol {
    func getHistory() async -> [ClipItem]
    func startMonitoring() async
    func copyToClipboard(_ content: String, fromEditor: Bool) async
    func clearAllHistory() async
    func togglePin(for item: ClipItem) async -> Bool
}

actor ModernClipboardService: ModernClipboardServiceProtocol {
    static let shared = ModernClipboardService()

    private var _history: [ClipItem] = []
    private var pollingTask: Task<Void, Never>?
    private let state = ClipboardState()
    private var lastEventTime = Date()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var currentInterval: TimeInterval = 0.5
    private let minInterval: TimeInterval = 0.5
    private let maxInterval: TimeInterval = 1.0

    // async関数として履歴を提供
    func getHistory() async -> [ClipItem] {
        _history
    }

    func startMonitoring() async {
        pollingTask?.cancel()
        pollingTask = Task { await startPollingLoop() }
    }

    private func startPollingLoop() async {
        while !Task.isCancelled {
            await checkClipboard()

            // 動的間隔を計算
            let newInterval = calculateInterval()
            if newInterval != currentInterval {
                currentInterval = newInterval
            }

            // 次のチェックまで待機
            try? await Task.sleep(for: .seconds(currentInterval))
        }
    }

    private func calculateInterval() -> TimeInterval {
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        if timeSinceLastEvent > 10 {
            return min(maxInterval, currentInterval * 1.1)
        } else {
            return max(minInterval, currentInterval * 0.9)
        }
    }

    private func checkClipboard() async {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // 変更があった場合（MainActor経由で読み出す）
        if let content = await MainActor.run(body: {
            pasteboard.string(forType: .string)
        }) {
            let hash = content.hashValue

            // 重複チェック
            let isDuplicate = await state.checkDuplicate(hash)
            if !isDuplicate && !(await state.getInternalCopy()) {
                let item = ClipItem(
                    content: content,
                    isFromEditor: await state.getFromEditor()
                )
                _history.insert(item, at: 0)
                lastEventTime = Date()

                // 履歴サイズ制限
                if _history.count > 1000 {
                    _history.removeLast()
                }
            }
        }

        // フラグをリセット
        await state.setInternalCopy(false)
        await state.setFromEditor(false)
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) async {
        await state.setInternalCopy(true)
        await state.setFromEditor(fromEditor)

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        }
    }

    func clearAllHistory() async {
        _history.removeAll()
    }

    func togglePin(for item: ClipItem) async -> Bool {
        if let index = _history.firstIndex(where: { $0.id == item.id }) {
            _history[index].isPinned.toggle()
            return _history[index].isPinned
        }
        return false
    }
}

// 状態管理用Actor
actor ClipboardState {
    private var isInternalCopy = false
    private var isFromEditor = false
    private var recentHashes: [Int] = []  // 配列で順序を保持

    func getInternalCopy() -> Bool { isInternalCopy }
    func setInternalCopy(_ value: Bool) { isInternalCopy = value }

    func getFromEditor() -> Bool { isFromEditor }
    func setFromEditor(_ value: Bool) { isFromEditor = value }

    func checkDuplicate(_ hash: Int) -> Bool {
        if recentHashes.contains(hash) {
            return true
        }

        recentHashes.append(hash)
        if recentHashes.count > 50 {
            recentHashes.removeFirst()  // 最古を削除
        }
        return false
    }
}
```

### 呼び出し側コードの移行

```swift
// MainViewModel.swift（抜粋）
@MainActor
final class MainViewModel: ObservableObject {
    @Published private(set) var history: [ClipItem] = []
    private let clipboardService: ModernClipboardServiceProtocol
    private var monitorTask: Task<Void, Never>?

    init(clipboardService: ModernClipboardServiceProtocol = ModernClipboardService.shared) {
        self.clipboardService = clipboardService

        monitorTask = Task {
            await clipboardService.startMonitoring()
            while !Task.isCancelled {
                history = await clipboardService.getHistory()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    func copyEditor() {
        Task { await clipboardService.copyToClipboard(editorText, fromEditor: true) }
    }
}

// MenuBarApp.swift（抜粋）
@main
struct MenuBarApp: App {
    @State private var clipboardService: ModernClipboardServiceProtocol = ModernClipboardService.shared

    var body: some Scene {
        MenuBarExtra("Kipple", systemImage: "doc.on.clipboard") {
            Button("Start Monitoring") {
                Task { await clipboardService.startMonitoring() }
            }
        }
    }
}
```

- `Kipple/Presentation/Features/Main/ViewModels/MainViewModel.swift`：`clipboardService`呼び出しを`Task { await ... }`に置き換え、履歴更新を`Task`ループで取得する。
- `Kipple/App/MenuBarApp.swift`：メニューアクションを`Task`経由で呼び出す。
- `Kipple/Presentation/Features/Settings/Views/DataSettingsView.swift`：自動クリア関連メソッドを`async`に更新し、`Task`で呼び出す。
- `Kipple/Domain/Services/ClipboardServiceProtocol.swift`および`KippleTests/Helpers/MockClipboardService.swift`：`async`メソッドに合わせてプロトコル定義とテストダブルを更新。
- 各種テスト（`KippleTests/…`）：`await`と`XCTExpectations`を用いた非同期テストに書き換える。
- `ClipboardServiceProvider`を更新し、macOS 13.0 以降では常に`ModernClipboardServiceAdapter.shared`を返し、旧OSのみ`ClipboardService.shared`へフォールバックするよう統一する。

### 新API導入時に重点確認する項目
- **Swift Concurrency × Combine**：現行コードはCombineベースのデバウンスやNotification購読を多用している。Observationマクロへ移行する場合、`PassthroughSubject`や`NotificationCenter`購読が残る箇所（設定変更など）をどう橋渡しするか設計する。
- **SwiftData移行**：`CoreDataClipboardRepository`はバッチ削除・バックグラウンドタスク・WALチューニングを実装済み。SwiftDataで同等性能を確保できるか、必要なら独自の同期処理やマイグレーションユーティリティを実装する。
- **Hotkey管理**：Carbon APIはイベントループとグローバルハンドラを使っている。`KeyboardShortcuts`へ置き換える際は、設定保持（`UserDefaults`キー）とテスト用モックの差し替え方法を決める。
- **Text編集コンポーネント**：`SimpleLineNumberView`はTextKit1を前提。TextKit2ラッパー（STTextView）を採用するなら、LineNumberやIME処理などのカスタムロジックが既存の要件を満たすか検証する。
- **SwiftDataリポジトリ**：`CoreDataClipboardRepository`は`save/load/loadAll/delete/clear`と`ClipItem`変換ヘルパーを持つ。SwiftDataで代替する場合、これらのAPIを再実装し、データ移行時のスキーマ互換を図る設計を加えておく。

### テスト観点での準備事項
- `ClipboardServiceTests`や`ClipboardServiceIntegrationTests`はTimer/RunLoopを直接駆動しているため、Async化後は`Task`ベースのテストヘルパーを用意し直す必要がある。
- `AsyncTerminationTests`は`flushPendingSaves()`がCore Dataへ即時保存する前提なので、SwiftDataで同等APIを提供できるか確認する。
- Mock実装（`MockClipboardService`など）は同期APIに依存している。async対応時にテストが破綻しないよう、ObservationやDependency Injectionの調整方針を文書化しておく。
- `PerformanceTests`は大量アイテム追加やピン操作を繰り返すベンチマークがあり、非同期化後にスループットが変動しないか要確認。
- `ModernClipboardServiceTests`や`ClipboardServiceProviderTests`のように、フラグ切替時に正しい型が返るか・履歴が更新されるかを検証するユニットテストを追加する。


### 2. Core Data → SwiftData

```swift
// SwiftDataModels.swift
import SwiftData

@Model
final class ClipItemModel {
    @Attribute(.unique) var id: UUID
    var content: String
    var timestamp: Date
    var isPinned: Bool
    var category: String?
    var appName: String?
    var bundleId: String?

    init(content: String, isPinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
    }
}

// SwiftDataRepository.swift
@MainActor
class SwiftDataRepository: ClipboardRepositoryProtocol {
    private let container: ModelContainer

    init() throws {
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func save(_ items: [ClipItem]) async throws {
        let context = container.mainContext
        items.forEach { item in
            let model = ClipItemModel(from: item)
            context.insert(model)
        }
        try context.save()
    }
}
```

> 補足: Core Data版とAPI互換にするため、`ClipItemModel(from:)` / `ClipItem(from:)` の双方向変換や `load` / `loadAll` / `delete` / `clear` なども合わせて実装し、マイグレーション時のデータ整合性を検証する。

### 3. @Published → @Observable

```swift
// NewMainViewModel.swift
import Observation

@Observable
@MainActor
final class MainViewModel {
    var editorText = "" {
        didSet { scheduleAutoSave() }
    }
    var history: [ClipItem] = []
    var pinnedItems: [ClipItem] = []

    private let clipboardService = ModernClipboardService.shared
    private var saveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init() {
        editorText = UserDefaults.standard.string(forKey: "lastEditorText") ?? ""
        startRefreshing()
    }

    private func startRefreshing() {
        refreshTask = Task {
            while !Task.isCancelled {
                // 履歴を定期的に更新
                await refreshHistory()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    private func refreshHistory() async {
        let items = await clipboardService.getHistory()
        if history != items {  // 変更があった場合のみ更新
            history = items
            pinnedItems = items.filter { $0.isPinned }
        }
    }

    func copyFromEditor() {
        Task {
            await clipboardService.copyToClipboard(editorText, fromEditor: true)
        }
    }

    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            if !Task.isCancelled {
                UserDefaults.standard.set(editorText, forKey: "lastEditorText")
            }
        }
    }
}
```

### 4. Carbon → KeyboardShortcuts

```swift
// NewHotkeyManager.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleKipple = Self("toggleKipple")
}

class HotkeyManager {
    func register() {
        KeyboardShortcuts.onKeyUp(for: .toggleKipple) {
            NotificationCenter.default.post(name: .toggleMainWindow, object: nil)
        }
    }
}
```

## 📦 必要な依存関係

```yaml
# project.yml に追加
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    exactVersion: 2.4.0

targets:
  Kipple:
    dependencies:
      - package: KeyboardShortcuts
```

## 🔄 移行手順（3-5日）

### Day 1-2: 新規実装
1. 依存関係追加（project.yml更新 → `make generate`）
2. 新規ファイル作成
   - `NewClipboardService.swift`
   - `SwiftDataModels.swift`
   - `NewMainViewModel.swift`
   - `NewHotkeyManager.swift`

### Day 3: データ移行
```swift
// DataMigrator.swift
class DataMigrator {
    static func migrateFromCoreData() async throws {
        // 既存のRepositoryを使用してデータ読み込み
        let oldRepo = CoreDataClipboardRepository()
        let oldData = try await oldRepo.loadAll()

        // SwiftDataへ保存
        let newRepo = try SwiftDataRepository()
        try await newRepo.save(oldData)
    }
}
```

### Day 4: 新実装の組み込み
```swift
// AppDelegate.swift
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 13.0, *) {
            Task {
                try? await DataMigrator.migrateFromCoreData()
                await ModernClipboardService.shared.startMonitoring()
            }
        } else {
            ClipboardService.shared.startMonitoring()
        }
    }
}

// レガシー実装は古いOS向けのフォールバックとして最小限残し、
// 対応OSでは常にModernClipboardServiceを利用する。
```

### Day 5: テストと最適化

## ⚙️ ビルド設定

```yaml
# project.yml の更新
settings:
  base:
    MACOSX_DEPLOYMENT_TARGET: 14.0  # SwiftData必須
    SWIFT_VERSION: 6.0
    # Apple Silicon専用（オプション）
    ARCHS: arm64
    EXCLUDED_ARCHS: x86_64
```

## ✅ 動作確認チェックリスト

### 必須機能
- [ ] クリップボード監視（0.5-1.0秒間隔）
- [ ] 履歴の保存と読み込み
- [ ] ピン留め機能
- [ ] エディタからのコピー判定
- [ ] ホットキー動作（⌃⌥M）
- [ ] 自動クリアタイマー

### パフォーマンス
- [ ] CPU使用率が既存と同等以下
- [ ] メモリ使用量が既存と同等以下
- [ ] 起動時間が3秒以内

### データ移行
- [ ] 既存の履歴データが移行される
- [ ] 設定が引き継がれる

## 🎯 期待される効果

- **コード削減**: 約50%（Core Data/NSLock/Timer関連）
- **可読性向上**: Actor/async-awaitで明確な並行処理
- **保守性向上**: 最新APIで将来性確保
- **パフォーマンス**: 同等以上（Actorによる効率的な並行処理）

## 📝 コンパイル時の注意点

1. **プロトコル更新の必要性**
   - ClipboardServiceProtocolを async/await 対応に更新が必要
   - MainViewModelの呼び出し側もawait対応が必要

2. **Strict Concurrency 対応**
   - Swift 6.2では`Sendable`/`@MainActor`チェックが強化される
   - 既存の`NSLock`や`DispatchQueue`依存コードをActor化・`@MainActor`化するロードマップを準備
   - `NSPasteboard`など非`Sendable`なAppKit型はMainActor経由で扱う設計に見直す

3. **SwiftData制約**
   - macOS 14.0以降が必須
   - Core Dataほど成熟していない

4. **外部依存ライブラリの互換性**
   - KeyboardShortcutsなど利用パッケージがSwift 6.2 / Xcode 26に対応しているか確認
   - 未対応の場合はアップデート待ちや代替ライブラリを検討

## 🏁 まとめ

AIによる一括実装で、複雑な段階的リリースは不要です。新規実装→検証→旧コード整理のシンプルな3ステップで、1週間以内に完全移行が可能です。

重要なのは**現在の機能を正確に理解し、新実装で完全に再現すること**です。巻き戻し用途のフィーチャーフラグは前提とせず、検証フェーズで十分にテストを行い、必要に応じてバックアップを確保してください。
