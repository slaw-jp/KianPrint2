# Contributing to KianPrint2

KianPrint2への不具合報告、改善案、pull requestを歓迎します。日本の裁判・法律実務向けの組版結果を扱うため、実事件の情報や秘密情報をIssue、サンプル、テストへ含めないでください。

## Issue

不具合を報告するときは、次を記載してください。

- KianPrint2とmacOSのバージョン
- 再現手順
- 期待した表示と実際の表示
- 問題を再現できる、架空の内容へ置き換えた最小の `.txt`

セキュリティ上の問題は公開Issueへ書かず、[SECURITY.md](SECURITY.md)に従ってください。

## Pull request

1. 変更範囲を一つの目的に絞ります。
2. パーサーまたは組版を変更する場合は回帰テストを追加します。
3. 入力文法を変更する場合はREADME、CHANGELOG、Samplesも更新します。
4. 次の検査を通します。

```sh
cd Packages/KianPrintCore
swift test
cd ../..
./Scripts/check-public.sh
git diff --check
```

コード、文書、サンプルはMIT Licenseの条件で提供されます。
