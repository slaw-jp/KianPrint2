#!/bin/sh
set -eu

tracked=$(git ls-files)
printf '%s\n' "$tracked"

if printf '%s\n' "$tracked" | grep -E '(^|/)(ResearchDownloads|PrivateDocuments)/|\.pdf$'; then
    echo "公開対象に研究PDFまたは非公開資料が含まれています。" >&2
    exit 1
fi

if git grep -n -E '([0-9]{2,4}-[0-9]{2,4}-[0-9]{3,4}|〒[0-9]{3}-[0-9]{4})' -- ':!README.md' ':!Samples/*' ':!Docs/*'; then
    echo "電話番号または郵便番号らしい文字列を確認してください。" >&2
    exit 1
fi

echo "公開対象の基本検査に合格しました。"
