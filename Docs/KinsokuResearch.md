# 日本語禁則処理の調査

調査日: 2026-09-07

## Microsoft公開仕様

第一資料はMicrosoft Open Specificationsの [`kinsoku`](https://learn.microsoft.com/ja-jp/openspecs/office_standards/ms-oe376/1ed6a072-e2ec-4b71-a42d-20f007bd097d) とした。

- WordprocessingMLの `kinsoku` は、東アジア言語の段落に行頭・行末文字規則を適用する互換設定である。
- 規格本文が挙げる中国語（簡体・繁体）と日本語に加え、Wordは韓国語にも適用する。
- `overflowPunct` と同時に有効で同じ文字に作用するとき、Wordでは `overflowPunct` が優先する。これは句読点を行頭へ送る代わりに、行末側へ一定量はみ出させる挙動を設計する根拠になる。
- OOXMLの設定は「どの文字をどう調整するか」という完全な改行アルゴリズムを規定しないため、裁判所文書の観察と回帰fixtureを併用する必要がある。

補助資料としてPowerPoint側の [東アジア言語別kinsoku設定](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/c02a5399-b358-4f4e-8e42-ad4fbb0e5261) も確認した。言語タグと禁則規則が結び付く点を確認するための資料であり、KianPrint2の行分割をPowerPoint互換にするものではない。

## 最高裁判所PDFの観察

[裁判所公式の「最近の最高裁判例」](https://www.courts.go.jp/hanrei/search2/index.html?courtCaseType=1&filter%5Brecent%5D=1) に2026-09-07時点で掲載された10件を確認した。PDF本体はリポジトリへ保存していない。

| 裁判日 | 裁判所・種別 | 事件番号 | 公式全文PDF | 主な観察 |
|---|---|---|---|---|
| 令和8年8月31日 | 最高裁第二小法廷・決定 | 令和8(し)770 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96994.pdf) | 算用階層 `１`、丸括弧数字 `⑴`、片仮名 `ア` を使用。句読点や閉じ括弧は行頭へ残さない。 |
| 令和8年8月28日 | 最高裁第二小法廷・判決 | 令和6(受)2169 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96970.pdf) | 長い日本語本文で句読点を行末側に保持。括弧内語句も自然な文字境界で折り返す。 |
| 令和8年7月16日 | 最高裁第一小法廷・判決 | 令和6(オ)720ほか | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96798.pdf) | `Ｘ１` 等の英字・数字混在、参照事件番号の括弧を含む。短い本文でも同じ階層字下げ。 |
| 令和8年7月13日 | 最高裁第一小法廷・判決 | 令和6(行ヒ)281 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96761.pdf) | 複数桁の項番号と長い行政用語が混在。行末をそろえつつ日本語文字単位で折り返す。 |
| 令和8年7月10日 | 最高裁第二小法廷・判決 | 令和7(さ)1 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96742.pdf) | 刑事事件の短い判決。全角数字、括弧、法律条文番号の連続を分断しすぎない。 |
| 令和8年7月7日 | 最高裁第三小法廷・判決 | 令和6(受)1694 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96730.pdf) | 長い複合語と読点が連続する民事判決。読点を次行頭へ送らない。 |
| 令和8年6月23日 | 最高裁第三小法廷・判決 | 令和6(行ヒ)160 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96536.pdf) | 法律名、年号、条項数字、丸括弧が密集するが、括弧開始を前行末へ孤立させない。 |
| 令和8年6月22日 | 最高裁第三小法廷・決定 | 令和8(ク)407 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96677.pdf) | 決定文でも同じ本文幅・階層・句読点処理。ページ番号は上部の `- n -` 形式。 |
| 令和8年6月17日 | 最高裁第三小法廷・決定 | 令和6(許)30 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96463.pdf) | 長い判示事項、複数の条項番号、括弧が混在。テキスト抽出可能なベクターPDF。 |
| 令和8年6月16日 | 最高裁第三小法廷・判決 | 令和5(行ヒ)366 | [全文](https://www.courts.go.jp/assets/hanrei/hanrei-pdf-96174.pdf) | 外国通貨等の語と条文引用が混在。日本語の文字境界と語句まとまりを併用。 |

共通して、本文は選択可能なテキストで、句読点・閉じ括弧・小書き仮名を行頭へ孤立させず、開き括弧を行末へ孤立させない組版が基調である。文書ごとに余白や一行字数を完全一致させるのではなく、この境界規則をKianPrint2の目標とする。

## β版の実装方針

`KianLineBreaker` はCore Textで各grapheme clusterの実幅を測り、次の順で決める。

1. 指定幅に収まる最大のgrapheme cluster境界を求める。
2. 開き括弧等が行末になる場合は次行へ送る。
3. 句読点、閉じ括弧、小書き仮名等が次行頭になる場合は、`overflowPunct` に相当する簡易ぶら下げとして前行へ含める。
4. ASCII英数字の語中で切れそうな場合、同じ行に語頭を置けるなら語頭まで戻す。
5. 確定範囲からCTLineを生成し、画面とPDFへ同じものを描く。

対象文字集合と短い架空fixtureは `TypographyTests.swift` に置く。実判決本文は転載しない。今後、実運用で差異が見つかったときは、その境界だけを再現する架空の短文を追加する。
