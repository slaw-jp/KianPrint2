# KianPrint2 リリース手順

KianPrint2だけを対象に、リリース候補を検証してGitHub Releaseとして公開する。`AGENTS.md` とワークスペース共通の `RELEASING.md` を併読する。「この変更をリリースして」で、この個別手順の全工程を対象製品だけに実施する。共通の `~/Development/publish-releases.sh "KianPrint2"` は対象限定のDrive配布用であり、GitHub Releaseの代わりにはならない。

以下のPrivateからPublicへの変更は初回OSS公開時の手順。既にPublicのリポジトリでは可視性を変更せず、同じ検証・ビルド・タグ・Release作成／公開を行う。通常のリリース指示にはリポジトリの可視性変更を含めない。

## このMacへのローカルインストール

「動作確認できる状態にして」「この変更をリリースして」のどちらでも、
`build/Release/KianPrint2.app` を **`/Users/hiroki/Applications/KianPrint2.app`** へインストールする。
既存版もこの場所で更新し、`/Applications/KianPrint2.app` には戻さない。
設定・保存データは `/Users/hiroki/Library` にある元の場所を継続使用する。
ステージング・署名検証・入替え方法は共通 `RELEASING.md` のアプリ節に従う。
配布ZIPの出力先とGitHub Releaseの公開先は従来どおり。

## 原則

- 異なるバイナリには必ず異なるバージョンまたはbuild numberを付ける。
- β版のtagは `vX.Y.Z-beta.N` とする。
- tagはannotated tagにする。
- Releaseビルド時点のworking treeをcleanにし、tagから同じソースを取得できるようにする。
- `build/` と配布ZIPはGitへコミットしない。
- リポジトリのPublic化は、履歴・成果物・リリース文面の確認後に最後に行う。

## 1. バージョンと文書

次を同時に更新する。

- `KianPrint2.xcodeproj/project.pbxproj` のDebug／Release両方の `MARKETING_VERSION`
- 同ファイルの `CURRENT_PROJECT_VERSION`
- `README.md` 冒頭のβ版、アプリバージョン、tag
- `CHANGELOG.md`

## 2. ソース検査

```sh
cd Packages/KianPrintCore
swift test
cd ../..
./Scripts/check-public.sh
git diff --check
```

実事件資料、秘密情報、証明書、個人用設定、研究PDFがtracked対象だけでなくGit履歴にも含まれていないことを確認する。コミットに公開したくない氏名・メールアドレスが使われていないことも確認する。

## 3. リリースコミット

差分を確認してリリース候補をコミットする。

```sh
git status --short
git diff --check
git add <確認済みのファイル>
git commit -m "Release 0.3.0-beta.1"
git status --short
```

最後の `git status --short` は何も表示しないこと。

## 4. PrivateのままReleaseビルド

```sh
xcodebuild -project KianPrint2.xcodeproj -scheme KianPrint2 \
  -configuration Release SYMROOT="$PWD/build" build
```

出力は `build/Release/KianPrint2.app`。現在はDeveloper IDを設定せずad-hoc署名する。arm64とx86_64を含むUniversal Binaryとして配布する。

バージョンと署名を確認する。

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  build/Release/KianPrint2.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  build/Release/KianPrint2.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 build/Release/KianPrint2.app
```

全サンプルを開き、再読み込み、ウインドウ縮小、PDF書き出しをReleaseアプリで確認する。

## 5. ZIPとチェックサム

```sh
ditto -c -k --sequesterRsrc --keepParent \
  build/Release/KianPrint2.app \
  build/Release/KianPrint2-0.3.0-beta.1-macOS-universal.zip
shasum -a 256 build/Release/KianPrint2-0.3.0-beta.1-macOS-universal.zip
```

表示されたSHA-256はGitHub Releaseの本文へ記載する。

## 6. tagとPrivateへのpush

```sh
git tag -a v0.3.0-beta.1 -m "KianPrint2 0.3.0-beta.1"
git push origin main
git push origin v0.3.0-beta.1
```

既存tagを確認してから作成し、公開済みtagを付け替えない。

## 7. GitHub Releaseの下書き

Privateの状態で、tagを指定したpre-releaseの下書きを作り、ZIPを添付する。

```sh
gh release create v0.3.0-beta.1 \
  build/Release/KianPrint2-0.3.0-beta.1-macOS-universal.zip \
  --title "KianPrint2 0.3.0-beta.1" \
  --prerelease --draft --notes-file <release-notes-file>
```

## 8. Public化とRelease公開

GitHubのリポジトリ設定でvisibilityをPublicへ変更する。Public化すると、全commit、branch、tag、Actionsの履歴とログが閲覧可能になるため、変更直前にもう一度確認する。

その後、GitHub Releaseの下書きを確認して公開する。ログアウト状態またはプライベートブラウズで次を確認する。

- README、LICENSE、SECURITYが閲覧できる。
- ReleaseがPre-releaseとして表示される。
- ZIPを認証なしでダウンロードできる。
- ZIPのSHA-256がRelease本文と一致する。

## 将来のDeveloper ID署名

現在のad-hoc署名版は、ダウンロード後の初回起動時にGatekeeperの警告が出る。警告なしで配布する段階ではApple Developer Programへ登録し、Developer ID Application署名、notarization、staplingを導入してからリリース手順を更新する。
