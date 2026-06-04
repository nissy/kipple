# Kipple

![Kipple icon](https://github.com/user-attachments/assets/2c295e8a-2fcd-4102-8e46-75bcbaaa79d9)

Kipple は、macOS 向けのローカル完結型クリップボードマネージャーです。

コピーしたテキストを検索しやすく、編集しやすく、整理しやすい状態で保存します。文章作成、調査、コーディング、フォーム入力、アプリ間の情報移動など、テキストを何度もコピーする作業に向いています。

[最新版をダウンロード](https://github.com/nissy/kipple/releases/latest/download/Kipple.dmg)

<img width="755" height="775" src="https://github.com/user-attachments/assets/4c4e2b1f-8055-43d8-82f6-25496d6975df" alt="Kipple のメインウィンドウ" />

## Why Kipple?

Kipple は、単なるクリップボード履歴リストではありません。

- コピーしたテキストを検索してすぐに戻せる
- 重要なクリップをピン留めできる
- Live Editor で貼り付け前や保存前に編集できる
- JSON と YAML をエディタ上で整形できる
- Queue で複数のクリップを順番に貼り付けられる
- OCR で画面上の文字を取り込める
- クリップボード履歴を Mac の中に保存できる

## Features

### Clipboard History

Kipple はコピーしたテキストを自動で保存し、メニューバーから開けるコンパクトなウィンドウに表示します。履歴項目を選ぶと、その内容がクリップボードへ戻ります。

履歴には次の情報を含められます。

- コピーしたテキスト
- コピー日時
- コピー元アプリ
- コピー元ウィンドウ名
- URL 分類
- ピン留め状態
- ユーザーカテゴリ

同じ内容を再コピーした場合は、重複を増やさず既存の項目を先頭へ移動します。

### Search, Pin, and Categories

クリップボード内容とコピー元アプリ名から履歴を検索できます。よく使う項目はピン留めし、組み込みカテゴリや独自カテゴリで整理できます。

Kipple には `None` と `URL` の組み込みカテゴリがあります。名前と SF Symbols アイコンを指定して、独自カテゴリを追加することもできます。

### Live Editor

Live Editor では、現在のクリップボード内容を確認し、編集してから履歴へ保存できます。

できること:

- 現在のクリップボード内容を編集
- 編集したテキストを履歴へ保存
- 前後の空白や改行をトリム
- JSON を整形
- YAML を整形

### Queue Paste

Queue は、複数の履歴項目を指定した順番で貼り付ける機能です。

Queue をオンにして履歴からクリップを選び、`Command + V` を繰り返し押すだけで、Kipple が次の項目へ進めます。Loop モードではキューを繰り返せます。

フォーム入力、定型データの転記、複数の値をアプリ間で移す作業に便利です。

### Screen Text Capture

Screen Text Capture では、画面上の範囲を選択して macOS Vision OCR でテキストを抽出できます。

認識したテキストはクリップボードへコピーされ、履歴にも保存されます。OCR 処理は Mac の中で完結します。

### Paste on Selection

Paste on Selection を使うと、履歴項目を選んだときに、直前に使っていたアプリへ直接貼り付けられます。履歴選択と貼り付けをまとめたい場合に便利です。

## Privacy

Kipple はローカル完結型です。

- クリップボード履歴は Mac の中に保存
- 設定はローカルに保存
- カテゴリはローカルに保存
- OCR は端末内で処理
- 分析なし
- トラッキングなし
- クラウド同期なし

Kipple はクリップボード履歴を外部サービスへ送信しません。

## Installation

1. [Releases](https://github.com/nissy/kipple/releases) から最新版をダウンロードします。
2. `Kipple.app` を Applications フォルダへ移動します。
3. Applications または Spotlight から Kipple を起動します。
4. 必要に応じてホットキーや設定を変更します。

## Requirements

- macOS 14.0 以降

## License

MIT License
