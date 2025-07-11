# Kipple Core Data 移行タスク

## 概要
UserDefaults による履歴保存（最大100件）から Core Data による無制限保存への移行を実装する。

## 移行の目的
- 設定通りの履歴件数（最大1000件）を永続化可能にする
- 検索・フィルタリング性能の向上
- 将来的な機能拡張（全文検索、タグ機能等）への対応

## アーキテクチャ設計

### 1. Core Data スタック構成
```
Kipple.xcdatamodeld/
├── ClipItemEntity
│   ├── id: UUID
│   ├── content: String
│   ├── timestamp: Date
│   ├── isPinned: Boolean
│   ├── kind: String
│   ├── sourceApp: String?
│   ├── windowTitle: String?
│   ├── bundleIdentifier: String?
│   ├── processID: Integer32
│   └── isFromEditor: Boolean
└── Indexes
    ├── timestamp (降順)
    └── isPinned
```

### 2. レイヤー構成
- **既存**: ClipboardService → ClipboardRepository → UserDefaults
- **新規**: ClipboardService → ClipboardRepository → CoreDataStack → Core Data

## 実装タスク

### Phase 1: Core Data 基盤構築

#### Task 1.1: Core Data モデル作成
- [ ] Kipple.xcdatamodeld ファイルを作成
- [ ] ClipItemEntity エンティティを定義
- [ ] 必要な属性とインデックスを設定
- [ ] NSManagedObject サブクラスを生成

#### Task 1.2: CoreDataStack 実装
- [ ] `Infrastructure/Persistence/CoreDataStack.swift` を作成
- [ ] NSPersistentContainer の初期化
- [ ] バックグラウンドコンテキストの設定
- [ ] エラーハンドリング実装

```swift
class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Kipple")
        container.loadPersistentStores { _, error in
            if let error = error {
                Logger.shared.error("Core Data failed to load: \(error)")
            }
        }
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask(block)
    }
}
```

### Phase 2: リポジトリ層の更新

#### Task 2.1: リポジトリプロトコル定義
- [ ] `ClipboardRepositoryProtocol` を作成
- [ ] 既存の ClipboardRepository をリファクタリング
- [ ] CoreDataClipboardRepository を新規実装

#### Task 2.2: CoreDataClipboardRepository 実装
- [ ] `Data/Repositories/CoreDataClipboardRepository.swift` を作成
- [ ] CRUD 操作の実装
  - [ ] save() - バックグラウンドで保存
  - [ ] load() - 初期は最新100件、残りは遅延読み込み
  - [ ] delete() - 個別削除
  - [ ] clear() - 全削除（ピン留め除く）
- [ ] バッチ削除の実装（パフォーマンス最適化）

```swift
class CoreDataClipboardRepository: ClipboardRepositoryProtocol {
    private let coreDataStack = CoreDataStack.shared
    
    func load(limit: Int = 100) async -> [ClipItem] {
        let context = coreDataStack.viewContext
        let request: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
        request.fetchLimit = limit
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.returnsObjectsAsFaults = false // 初期読み込みは完全取得
        
        do {
            let entities = try context.fetch(request)
            return entities.map { $0.toClipItem() }
        } catch {
            Logger.shared.error("Failed to load from Core Data: \(error)")
            return []
        }
    }
    
    func loadRemaining(offset: Int) async -> [ClipItem] {
        // バックグラウンドで残りを読み込み
    }
}
```

### Phase 3: 切り替え実装

#### Task 3.1: リポジトリ切り替え
- [ ] ClipboardService でリポジトリを CoreDataClipboardRepository に変更
- [ ] 既存の UserDefaults データはクリア（移行不要）
- [ ] 初回起動時の空データ対応

### Phase 4: ClipboardService の更新

#### Task 4.1: 非同期対応
- [ ] ClipboardService を非同期初期化に対応
- [ ] 初期読み込みの最適化（最新100件のみ）
- [ ] バックグラウンドでの追加読み込み

#### Task 4.2: リポジトリ切り替え
- [ ] 依存性注入でリポジトリを切り替え可能に
- [ ] フィーチャーフラグでの段階的移行対応

### Phase 5: UI の更新

#### Task 5.1: 読み込み状態の表示
- [ ] 初期読み込み中のローディング表示
- [ ] 追加読み込み中のインジケーター

#### Task 5.2: パフォーマンス最適化
- [ ] LazyVStack の最適化
- [ ] プリフェッチング実装

### Phase 6: テスト

#### Task 6.1: 単体テスト
- [ ] CoreDataStack のテスト
- [ ] CoreDataClipboardRepository のテスト
- [ ] 移行ロジックのテスト

#### Task 6.2: 統合テスト
- [ ] 大量データ（1000件）での動作確認
- [ ] 起動時間の計測
- [ ] メモリ使用量の確認

#### Task 6.3: 既存テストの更新
- [ ] ClipboardRepositoryTests の更新
- [ ] ClipboardServiceTests の更新
- [ ] MainViewModelTests の更新

### Phase 7: 最適化とクリーンアップ

#### Task 7.1: パフォーマンスチューニング
- [ ] インデックスの最適化
- [ ] フェッチリクエストの最適化
- [ ] メモリ使用量の最適化

#### Task 7.2: コードクリーンアップ
- [ ] 旧 ClipboardRepository の削除（または Deprecated 化）
- [ ] 不要になった定数（maxStoredItems = 100）の削除
- [ ] ドキュメント更新

## 実装順序

1. **Week 1**: Phase 1-2（Core Data 基盤とリポジトリ）
2. **Week 2**: Phase 3-4（切り替えとサービス層）
3. **Week 3**: Phase 5-6（UI更新とテスト）
4. **Week 4**: Phase 7（最適化とリリース準備）

## リスクと対策

### リスク 1: 初回起動時の空データ
- **対策**: 適切な初期状態の表示、ユーザーへの通知

### リスク 2: パフォーマンス劣化
- **対策**: 段階的読み込み、適切なインデックス、プロファイリング

### リスク 3: 既存機能の破壊
- **対策**: フィーチャーフラグ、段階的リリース、包括的なテスト

## 成功基準

- [ ] 1000件の履歴を保存・復元できる
- [ ] 起動時間が現在の実装から +50ms 以内
- [ ] 検索・フィルタリングが高速化（100ms → 10ms）
- [ ] すべての既存テストがパス
- [ ] メモリ使用量が適切（1000件で 50MB 以下）

## 参考資料

- [Apple Core Data Programming Guide](https://developer.apple.com/documentation/coredata)
- [Core Data Best Practices](https://developer.apple.com/videos/play/wwdc2023/10064/)
- [Efficient Core Data](https://www.objc.io/books/core-data/)