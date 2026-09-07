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

## Markdownパーサ選定

2026-09-07時点の `swiftlang/swift-markdown` 最新リリース0.8.0を検討した。同ライブラリはGFM ASTと表を提供する一方、KianPrint2では日本語Directiveの前処理、旧式行単位記法、厳密なsource line mapping、軽量な配布を優先する。β版の対象構文は限定されているため、依存を追加せず専用ブロックパーサを採用した。

現在のパーサはGFM全体を実装するものではない。対象は見出し、太字、斜体、引用、パイプ表、セル内 `<br>`、日本語Directiveである。将来構文範囲を広げる場合は0.8.0以降へ固定してAST部分を置換できるよう、出力先を `KianDocument` に隔離している。
