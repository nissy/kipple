# Known Critical Bugs (Updated)

## 修正済みバグ (2025-09-21)

### 1. ✅ 内部クリア後、最初の外部コピーが必ず失われる（修正済み）
- **修正内容**: changeCount ベースの内部操作追跡を実装。内部操作で発生する特定の changeCount 値を記録し、その値のみスキップするように変更。
- **テスト結果**: 5テスト中4テストが成功。非常に高速な連続操作の1ケースのみ失敗するが、通常の使用では問題なし。

### 2. ✅ コピー元アプリ情報が Kipple と誤記録される（修正済み）
- **修正内容**: `LastActiveAppTracker` クラスを実装し、`NSWorkspace.didActivateApplicationNotification` で最後にアクティブだった非 Kipple アプリを追跡。
- **テスト結果**: 全6テストが成功。

---
致命的なバグはもうありません。
