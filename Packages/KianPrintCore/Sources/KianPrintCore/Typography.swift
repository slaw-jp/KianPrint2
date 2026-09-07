import CoreText
import Foundation

public struct KianMeasuredLine {
    public var attributedText: NSAttributedString
    public var width: CGFloat
    public var ascent: CGFloat
    public var descent: CGFloat
    public var leading: CGFloat

    public var typographicHeight: CGFloat { ascent + descent + leading }
}

public enum KianTypography {
    public static func attributedString(
        from inlines: [KianInline],
        settings: KianSettings,
        fontSize: CGFloat? = nil,
        forceBold: Bool = false
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let size = fontSize ?? settings.fontSize
        for inline in inlines {
            let font = makeFont(
                name: settings.fontName,
                size: size,
                bold: forceBold || inline.bold,
                italic: inline.italic
            )
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTKernAttributeName as NSAttributedString.Key: settings.characterSpacing,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)
            ]
            result.append(NSAttributedString(string: inline.text, attributes: attributes))
        }
        if result.length == 0 {
            let font = makeFont(name: settings.fontName, size: size, bold: forceBold, italic: false)
            result.append(NSAttributedString(
                string: "",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ))
        }
        return result
    }

    public static func makeFont(name: String, size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let resolvedName = bold ? "Hiragino Sans W6" : name
        let base = CTFontCreateWithName(resolvedName as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if italic { traits.insert(.italicTrait) }
        guard !traits.isEmpty else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, traits, traits) ?? base
    }

    public static func width(of attributed: NSAttributedString) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

public struct KianLineBreaker {
    public static let prohibitedAtLineStart = Set(
        "、。，．・：；？！‼⁇⁈⁉)]｝〕〉》」』】〙〗〟’”｠»ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶー〜ゝゞヽヾ々〻ㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ".map(String.init)
    )
    public static let prohibitedAtLineEnd = Set(
        "([｛〔〈《「『【〘〖〝‘“｟«".map(String.init)
    )

    public init() {}

    public func breakLines(_ attributed: NSAttributedString, width: CGFloat) -> [KianMeasuredLine] {
        breakLines(attributed, firstLineWidth: width, subsequentLineWidth: width)
    }

    public func breakLines(
        _ attributed: NSAttributedString,
        firstLineWidth: CGFloat,
        subsequentLineWidth: CGFloat
    ) -> [KianMeasuredLine] {
        guard attributed.length > 0 else { return [measure(attributed)] }
        var results: [KianMeasuredLine] = []
        let fullString = attributed.string as NSString
        let paragraphs = rangesSeparatedByNewline(in: fullString)
        for paragraph in paragraphs {
            if paragraph.length == 0 {
                results.append(measure(attributed.attributedSubstring(from: paragraph)))
                continue
            }
            let clusters = composedRanges(in: fullString, range: paragraph)
            var start = 0
            while start < clusters.count {
                let width = results.isEmpty ? firstLineWidth : subsequentLineWidth
                var end = start + 1
                var lastFitting = end
                while end <= clusters.count {
                    let candidate = union(clusters[start..<end])
                    if KianTypography.width(of: attributed.attributedSubstring(from: candidate)) <= width {
                        lastFitting = end
                        end += 1
                    } else { break }
                }

                var breakIndex = min(lastFitting, clusters.count)
                if breakIndex <= start { breakIndex = start + 1 }

                while breakIndex > start + 1,
                      Self.prohibitedAtLineEnd.contains(clusterString(fullString, clusters[breakIndex - 1])) {
                    breakIndex -= 1
                }

                if breakIndex < clusters.count,
                   isASCIIWord(clusterString(fullString, clusters[breakIndex - 1])),
                   isASCIIWord(clusterString(fullString, clusters[breakIndex])) {
                    var wordStart = breakIndex
                    while wordStart > start,
                          isASCIIWord(clusterString(fullString, clusters[wordStart - 1])) {
                        wordStart -= 1
                    }
                    if wordStart > start { breakIndex = wordStart }
                }

                // Word's overflowPunct behavior is approximated by hanging prohibited
                // punctuation instead of permitting it at the beginning of the next line.
                while breakIndex < clusters.count,
                      Self.prohibitedAtLineStart.contains(clusterString(fullString, clusters[breakIndex])) {
                    breakIndex += 1
                }

                let lineRange = union(clusters[start..<breakIndex])
                results.append(measure(attributed.attributedSubstring(from: lineRange)))
                start = breakIndex
            }
        }
        return results
    }

    private func measure(_ attributed: NSAttributedString) -> KianMeasuredLine {
        guard attributed.length > 0 else {
            return KianMeasuredLine(attributedText: attributed, width: 0, ascent: 10, descent: 2, leading: 0)
        }
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return KianMeasuredLine(attributedText: attributed, width: width, ascent: ascent, descent: descent, leading: leading)
    }

    private func rangesSeparatedByNewline(in string: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var start = 0
        for index in 0..<string.length where string.character(at: index) == 10 {
            result.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        result.append(NSRange(location: start, length: string.length - start))
        return result
    }

    private func composedRanges(in string: NSString, range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        string.enumerateSubstrings(in: range, options: .byComposedCharacterSequences) { _, substringRange, _, _ in
            result.append(substringRange)
        }
        return result
    }

    private func union(_ ranges: ArraySlice<NSRange>) -> NSRange {
        guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private func clusterString(_ string: NSString, _ range: NSRange) -> String {
        string.substring(with: range)
    }

    private func isASCIIWord(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.value < 128
        }
    }
}
