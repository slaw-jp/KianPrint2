# KianPrint2

KianPrint2は、プレーンテキストを日本の裁判・法律実務向けA4文書として組版するmacOSアプリです。原稿は引き続き `mi.app` などのテキストエディタで編集し、KianPrint2はライブプレビューとPDF出力を担当します。

β版のバージョンは `0.1.0-beta.1` です。アプリの `CFBundleShortVersionString` はAppleの形式制約に従い `0.1.0`、リリースタグは `v0.1.0-beta.1` とします。

## 主な機能

- `.txt` をKian Markdown（GFMに近い表記＋日本語Directive）として解釈
- Core Textで文字幅を測り、独自の日本語禁則処理で改行
- 標準の「禁則処理: 裁判所」設定では、全角本文を37字×26行で組版
- 既存KianPrint互換の法律文書番号・ぶら下がりインデント
- 複数A4ページのベクタープレビューとズーム
- atomic saveにも追従するファイル監視と自動再読み込み
- 画面とPDFで同じページレイアウト・同じ描画経路を利用
- 通常表、証拠説明書、証拠調べ請求書、証拠意見書、附属書類、当事者目録、事件情報
- パースエラー時は直前の正常なプレビューを保持

## 基本ワークフロー

1. Finderまたはmi.appで `.txt` を開いて起案します。
2. mi.appのToolから保存してKianPrint2へ渡します。
3. 以後はmi.appで保存するたびにKianPrint2のプレビューが更新されます。
4. 必要になった時だけ「PDFを書き出す」を実行します。

mi.appのToolには次の形式を利用できます。

```text
<<<SAVE DROP(KianPrint2.app)>>>
```

Markdown一般の `.md` は別のエディタに関連付けたまま使えるよう、KianPrint文書の入力拡張子は意図的に `.txt` としています。

## 最小例

```markdown
---
文字サイズ: 12pt
上余白: 35mm
下余白: 27mm
左余白: 30mm
右余白: 22mm
ページ番号: あり
禁則処理: 裁判所
---

# 訴状

@右揃え {
令和8年9月7日
}

架空地方裁判所　御中

@右配置 {
〒000-0000
架空県架空市一丁目
原告訴訟代理人弁護士　架空太郎
}

第１　請求の趣旨

１　被告は、原告に対し、金100万円を支払え。
```

`@右揃え` は本文幅全体で右揃えにします。`@右配置` は内容幅の左揃えブロックを右側へ置くため、住所や事務所情報の各行の左端が揃います。

## 字間と行間

先頭のfront matterで文書ごとに指定できます。`Kern` に相当する設定名は `字間`、`Line Spacing` は `行間` です。どちらもpt単位で、`行間` は文字サイズに追加する間隔を表します。

```text
---
文字サイズ: 12pt
字間: 0pt
行間: 6pt
---
```

この例の行送りは18ptです。設定を省略した場合は先代KianPrintの裁判所書式（字間0pt、行間13.62pt）を使います。行間・字間・フォント・文字サイズまたは余白を変更した文書は、37字×26行の裁判所グリッドから自動的に外れ、実測幅で組版します。

## 表

```markdown
## 附属書類

| No. | 書類 | 数量 |
| ---: | --- | ---: |
| 1 | 訴状副本 | 1通 |
| 2 | 甲号証写し | 各2通 |
```

見出しと列名から表の意味を認識します。必要なら `@証拠説明書 { ... }` などの日本語Directiveで明示できます。証拠調べ請求書は横型Markdown表から縦型レコードへ、当事者目録は罫線なしレコードへ変換します。

## ビルドとテスト

必要環境はmacOS 13以降とXcodeです。外部パッケージへのネットワークアクセスは不要です。

```sh
xcodebuild -project KianPrint2.xcodeproj -scheme KianPrint2 \
  -configuration Release SYMROOT="$PWD/build" build

cd Packages/KianPrintCore
swift test
```

既存のDevelopmentワークスペースと同様に、証明書を要求しないad-hoc署名、`build/Release/KianPrint2.app` という出力場所、`MARKETING_VERSION` によるアプリ版管理を採用しています。詳しいリリース手順は [Docs/Releasing.md](Docs/Releasing.md) を参照してください。

## プライバシー

`Samples/` へ実事件資料を入れないでください。実在する当事者名、住所、電話番号、メールアドレス、事件番号、裁判所提出書面をコミットしないでください。研究用PDFは `ResearchDownloads/` に置くとGitから除外されます。

## 沿革

作者は2014年からLibreOffice / OpenOffice等を利用した法律文書自動整形スクリプトを公開してきました。

- [2014年の記事: miでOpenOfficeを操作する](https://www.slaw.jp/2014/12/miopenoffice.html)
- [macOSネイティブアプリKianPrintの記事](https://www.slaw.jp/2025/06/macos.html)

KianPrint2は、この思想をKian Markdown、独自組版、表、ライブプレビューへ発展させる後継プロジェクトです。既存KianPrintのソースを骨格として流用せず、互換動作を調査した上で新しく設計・実装しています。

## ライセンス

[MIT License](LICENSE)
