# アーキテクチャ

```text
.txt
  → KianParser
  → KianDocument（意味モデル）
  → KianLayoutEngine + KianLineBreaker
  → [KianPage]（配置済み描画コマンド）
     ├→ NSViewプレビュー
     └→ CGContext PDF
```

`Packages/KianPrintCore` はSwiftUI/AppKitに依存しないlocal Swift packageである。Parser、Model、Semantic、Typography、Layout、Tables、Renderingの責務は現在ファイル単位で分離し、将来のCLIでも同じCoreを使える。

プレビューとPDFは再レイアウトしない。どちらも同じ `KianPage` の文字・線・矩形コマンドを `KianRenderer.draw(page:in:)` で描く。画面用画像や中間PDFは作成しない。

ファイル監視は開いたファイル自身ではなく親ディレクトリへ `DispatchSourceFileSystemObject` を設定する。エディタが元ファイルを置換するatomic save後も監視対象ディレクトリは存続する。イベントは220ms debounceし、読み込みまたはパースに失敗した場合は最後の正常な `KianLayout` を保持する。

## 独自記法パーサ

2026-09-08、Markdownから独立したプレーンテキスト向け構文へ移行した。KianPrint2では、Tabで区切る `@table`／`@tab`、行末の `@right`／`@center`／`@size`、厳密なsource line mapping、軽量な配布を優先し、依存を追加しない専用パーサを使用する。

Markdown由来で解釈するのは行内の太字と斜体だけである。Markdown見出し、引用、パイプ表、セル内 `<br>` は解釈しない。先代KianPrint由来の全角空白による中央・右揃えは互換入力として残すが、KianPrint2で一時採用していた波括弧形式の `@table`／`@tab` は受け付けない。パーサーの出力先は引き続き `KianDocument` に隔離する。
