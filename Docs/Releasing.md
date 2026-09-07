# リリース手順

Developmentワークスペース内の既存macOSアプリと同じ原則を使う。

1. `CHANGELOG.md` を更新し、Xcode projectの `MARKETING_VERSION` とbuild numberを更新する。
2. `swift test` とReleaseビルドを実行する。
3. `Scripts/check-public.sh` でtracked対象を検査する。
4. 変更をコミットし、working treeがcleanであることを確認する。
5. annotated tag（β版では `v0.1.0-beta.1`）を作る。
6. Public GitHub repositoryへbranchとtagをpushする。

Releaseビルド:

```sh
xcodebuild -project KianPrint2.xcodeproj -scheme KianPrint2 \
  -configuration Release SYMROOT="$PWD/build" build
```

出力は `build/Release/KianPrint2.app`。既存アプリと同様にDevelopment Teamを設定せずad-hoc署名する。公開配布時にGatekeeper警告をなくすには、将来Developer ID署名とnotarizationを別途導入する。

KianPrint2はMITで公開するため、非公開ミラーを一括pushするワークスペース側スクリプトへ無条件に混ぜない。公開リポジトリのremoteを確認して個別にpushする。
