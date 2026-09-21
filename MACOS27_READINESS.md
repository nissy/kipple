# Kipple の macOS 27 対応結果

更新日: 2026-09-21。対象: macOS 27.0 以降、Apple Silicon。

## 修正した内容

旧 OS・旧データとの互換性を追加することなく、調査で見つかった終了・読み取り・権限表示・ログイン項目の問題を修正した。既存の利用者データを消去する変更は行っていない。

| 対象 | 修正後の動作 |
| --- | --- |
| 終了時の保存 | AppKit に `.terminateLater` を返し、未処理のコピーと履歴保存が完了してから終了を許可する。連続した終了要求でも保存を飛ばさない。保存失敗・10 秒のタイムアウトでは終了を取り消して案内する。タイムアウト後の遅い完了通知で終了しない |
| クリップボードの読み取り | `ClipboardReader` に取得と `NSPasteboard.accessBehavior` の判定を集約した。同じ内容への失敗を監視周期ごとに繰り返さず、許可状態の変更や明示的な再確認で読み直す。拒否後に許可された場合は、変更番号が同じでも取り込める |
| 初回の読み取り | 最初の取得に伴って OS のポリシーが変わっても、正常に取得できた内容を破棄しない。取得中に別のコピーが発生した場合は、その組み合わせを採用しない |
| 書式なし貼り付け | 読み取りが制限された場合と、履歴への退避に失敗した場合の案内を分けた。退避できないまま元の書式を消さない |
| ログイン時起動 | 保存済みの Bool ではなく `SMAppService.status` を表示する。承認待ちの表示・設定への導線・承認待ちの登録解除・OS 側の変更後の更新を追加した |
| 権限画面 | 画面収録、デバイスの制御とデータへのアクセス、クリップボードへのアクセスを機能と結び付けて表示する。読み取りの再確認を追加し、日本語の表示漏れも修正した |
| 診断ログ | OS・署名の識別情報、実際の権限判定、読み取りポリシー、エラーの domain/code を記録する。クリップボード本文は記録しない。実行ファイルのパスは private 扱い |
| 署名付きテスト | 本体とテストバンドルの Developer ID 署名を整合させた。Makefile の署名を無効にする指定を削除し、通常の署名設定でテストを実行できるようにした |
| メニュー・設定欄 | カテゴリのアイコン選択メニューをタイトルとアイコンの表示に変更した。7 箇所のテキスト欄を `.bordered` と `.textInputBorderShape(.roundedRectangle)` に更新した |
| 案内 | README の英語版・日本語版と FEATURES を更新した |

独立ウインドウの動作と既存の Liquid Glass の実装は維持している。入力監視やフルディスクアクセスを新たに要求する変更は行っていない。

## 検証結果

環境は macOS 27.0 / 26A428、Xcode 27.0 / 27A266a、Swift 6.4。`SWIFT_VERSION=6.0` は Swift 6 の言語モードであり、コンパイラのバージョンとは別の指定である。

| 検証 | 結果 |
| --- | --- |
| 署名付き全テスト | 664 件成功、失敗 0 件 |
| その後の読み取り・貼り付け・OCR 周辺の修正に対する関連テスト | 51 件成功、失敗 0 件 |
| 配布版 | `make build` 成功。Developer ID 署名と App Sandbox を維持 |
| MCP ヘルパー | 配布用ヘルパーの起動、初期接続、ツール定義、不正入力・文字数制限の検証に成功 |
| MCP の保存 | テスト専用ソケット、ファイル保存領域、ペーストボードを使い、登録後の履歴・タイトル・登録結果を再読込する結合テストが成功 |
| Release の App Group 通信 | 同じ署名・Sandbox の検証プログラムから本体へ接続し、バージョン不一致の応答を受信した。実際の通信経路を確認したもので、利用者の履歴へ登録した試験ではない |
| 終了時保存の実動作 | 本番の `ApplicationTerminationController` を使う AppKit 検証アプリで、ボタンによる終了要求後に `saved` → `reply=true` → `willTerminate` を確認し、プロセスの終了も確認した |
| 権限付与後 | 実行中の開発版で `screenCapture=true`、`accessibility=true`、`clipboardPolicy=2` をログで確認。設定画面でも両権限の「許可済み」とクリップボードの「読み取りは常に許可されています」を確認した |
| ショートカット設定 | 一般設定に書式なし貼り付け `⌃⇧V` が表示され、権限付与後は編集可能。一般設定の表示も確認した |
| 通常の貼り付け | 検証用 NSTextView に Command+V で貼り付け、内容の一致と太字の保持を確認した |
| 静的確認 | 変更した Swift ファイルの SwiftLint 違反 0 件、`git diff --check` 問題なし、日英 Localizable.strings の構文検証成功 |

全テストの初回実行では、監視の非同期起動を待たずに判定する既存テストが失敗した。実際の監視開始を待つ検証に修正した後、上記の全件成功を確認した。テストの無効化やスキップは行っていない。

配布版ビルドには `Metadata extraction skipped, no AppIntents.framework dependency found` という既存の警告が残る。現在の Kipple は AppIntents を実装していない。警告がゼロとはしていない。

## 実機でまだ確認できていない条件

- 自動操作による Control+Shift+V では、検証用画面への貼り付けを確認できなかった。グローバルショートカットへの自動キー入力の到達を切り分けられていないため、実キーでの操作確認を依頼中。650 ms 遅れて読む貼り付け先の実操作試験も未完了。権限が許可済みになったことだけを貼り付け成功とは扱わない。
- 権限の取り消し・再許可、ログアウト・シャットダウン、システム設定側からのログイン項目変更は、利用者の環境に影響するため実操作していない。状態遷移・終了の失敗・タイムアウトは注入可能な依存を用いたテストで確認した。
- Release ヘルパーから実際の Release 本体へ正常な履歴登録を行う試験と、アプリ未起動時の起動を含めた一連の試験は未実施。隔離した結合テストと、実際の App Group 通信はそれぞれ確認済み。
- OCR の初回範囲選択、複数画面・異なる倍率、日本語入力、エディタの詳細な選択操作、カテゴリメニュー、明暗・透明度・コントラストを変えた Glass の網羅的な目視確認は残る。

## 検証ログ

- [全 664 件のテスト](/Users/nishida/Projects/kipple/build/validation/macos27-fixes-suite-final.log)
- [関連 51 件のテスト](/Users/nishida/Projects/kipple/build/validation/macos27-fixes-focused-final.log)
- [配布版ビルドとヘルパー検証](/Users/nishida/Projects/kipple/build/validation/macos27-fixes-release-final.log)
- [Release の App Group 通信](/Users/nishida/Projects/kipple/build/validation/macos27-release-ipc.log)
- [AppKit 終了処理の実動作](/Users/nishida/Projects/kipple/build/validation/macos27-termination-runtime.log)
- [貼り付けの実動作](/Users/nishida/Projects/kipple/build/validation/macos27-paste-runtime.log)
- [最終変更を反映した開発版のビルド・起動](/Users/nishida/Projects/kipple/build/validation/macos27-fixes-run-final.log)

検証用プログラムは Git 管理外の `build/validation` に置いている。Git の登録・コミット・ブランチ変更は行っていない。

## 判断に使用した一次資料

- [Apple: macOS 27 リリースノート](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [Apple: Xcode 27 リリースノート](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [Apple: AppKit 更新履歴](https://developer.apple.com/documentation/updates/appkit)
- [Apple: 終了応答の契約](https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:))
- [Apple: NSPasteboard.accessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-86972)
- [Apple: SMAppService の承認待ち](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)
- [Apple: Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/)

クリップボードの制御 API 自体は macOS 15.4 から存在する。API が存在することと、macOS 27 で全アプリに新たな許可が一律必須になることは区別した。終了応答・ログイン項目の不足も、macOS 27 で初めて生じた問題とはしていない。
