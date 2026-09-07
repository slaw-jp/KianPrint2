import Foundation

public struct KianParser {
    public init() {}

    public func parse(_ source: String) throws -> KianDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var settings = KianSettings()
        var issues: [KianIssue] = []
        var cursor = 0

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            cursor = 1
            var foundEnd = false
            var settingRange: Range<Int>?
            while cursor < lines.count {
                if lines[cursor].trimmingCharacters(in: .whitespaces) == "---" {
                    foundEnd = true
                    settingRange = 1..<cursor
                    cursor += 1
                    break
                }
                cursor += 1
            }
            if !foundEnd {
                throw KianIssue(line: 1, message: "設定ブロックを閉じる --- がありません。")
            }
            if let settingRange {
                let pairs = try settingRange.compactMap { index in
                    try settingPair(lines[index], lineNumber: index + 1)
                }
                let presetRows = pairs.filter { $0.key == "preset" }
                if let invalid = presetRows.first(where: { $0.value.lowercased() != KianPreset.court.rawValue }) {
                    throw KianIssue(line: invalid.lineNumber, message: "未知のプリセット「\(invalid.value)」です。")
                }
                if !presetRows.isEmpty {
                    // The court preset is intentionally authoritative. All
                    // other front matter values are ignored, regardless of order.
                    settings = KianSettings()
                } else if !pairs.isEmpty {
                    settings.preset = nil
                    for pair in pairs {
                        try applySetting(pair, into: &settings, issues: &issues)
                    }
                }
            }
        }

        var recognizer = LegalNumberingRecognizer(allLines: lines)
        let blocks = try parseBlocks(
            lines: lines,
            range: cursor..<lines.count,
            recognizer: &recognizer
        )
        return KianDocument(settings: settings, blocks: blocks, issues: issues)
    }

    private func parseBlocks(
        lines: [String],
        range: Range<Int>,
        recognizer: inout LegalNumberingRecognizer
    ) throws -> [KianBlock] {
        var blocks: [KianBlock] = []
        var index = range.lowerBound

        while index < range.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blocks.append(.spacer(0))
                index += 1
                continue
            }
            if trimmed == "@page" {
                blocks.append(.pageBreak)
                index += 1
                continue
            }

            if trimmed.hasPrefix("@table") {
                let parsed = try parseNewTable(lines: lines, start: index, upperBound: range.upperBound)
                blocks.append(.table(parsed.table))
                index = parsed.nextIndex
                continue
            }
            if trimmed.hasPrefix("@tab") {
                let parsed = try parseNewTabbedBlock(lines: lines, start: index, upperBound: range.upperBound)
                blocks.append(.tabbed(parsed.block))
                index = parsed.nextIndex
                continue
            }

            if trimmed == "@end" || line.hasSuffix("@end") {
                throw KianIssue(line: index + 1, message: "@end は @table または @tab の最終データ行の末尾にだけ書けます。")
            }

            if index + 1 < range.upperBound,
               isTableRow(line),
               isTableSeparator(lines[index + 1]) {
                throw KianIssue(line: index + 1, message: "Markdown表は使用できません。@table(...) で始め、Tabでセルを区切り、最終行を @end で閉じてください。")
            }

            if trimmed.hasPrefix("@") {
                throw KianIssue(line: index + 1, message: "未知のDirective \(trimmed) です。")
            }

            if let legacy = legacyAlignedParagraph(line, sourceLine: index + 1) {
                blocks.append(legacy)
                index += 1
                continue
            }

            let styledLine = try parseLineStyle(line, line: index + 1)
            let indent = recognizer.indent(for: styledLine.text)
            blocks.append(.paragraph(KianParagraph(
                inlines: parseInline(styledLine.text),
                sourceLine: index + 1,
                indentLevel: indent.level,
                firstLineOutdent: indent.outdent,
                alignment: styledLine.alignment,
                fontSize: styledLine.fontSize,
                trailingInset: styledLine.trailingInset
            )))
            index += 1
        }
        return blocks
    }

    private func settingPair(
        _ line: String,
        lineNumber: Int
    ) throws -> (key: String, value: String, lineNumber: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let colon = trimmed.firstIndex(of: ":") ?? trimmed.firstIndex(of: "：") else {
            throw KianIssue(line: lineNumber, message: "設定は「項目: 値」の形式で書いてください。")
        }
        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value, lineNumber)
    }

    private func applySetting(
        _ pair: (key: String, value: String, lineNumber: Int),
        into settings: inout KianSettings,
        issues: inout [KianIssue]
    ) throws {
        let (key, value, lineNumber) = pair

        switch key {
        case "preset":
            guard value.lowercased() == KianPreset.court.rawValue else {
                throw KianIssue(line: lineNumber, message: "未知のプリセット「\(value)」です。")
            }
            settings = KianSettings()
        case "paper":
            guard value.uppercased() == "A4" else {
                throw KianIssue(line: lineNumber, message: "β版で使用できる用紙はA4だけです。")
            }
        case "font": settings.fontName = value
        case "font-size": settings.fontSize = try points(value, line: lineNumber)
        case "top": settings.topMargin = try millimeters(value, line: lineNumber)
        case "bottom": settings.bottomMargin = try millimeters(value, line: lineNumber)
        case "left": settings.leftMargin = try millimeters(value, line: lineNumber)
        case "right": settings.rightMargin = try millimeters(value, line: lineNumber)
        case "spacing": settings.lineSpacing = try points(value, line: lineNumber)
        case "kern": settings.characterSpacing = try points(value, line: lineNumber, unitOptional: true)
        case "page-number":
            if value.lowercased() == "on" { settings.showsPageNumbers = true }
            else if value.lowercased() == "off" { settings.showsPageNumbers = false }
            else { throw KianIssue(line: lineNumber, message: "page-number は on または off で指定してください。") }
        case "kinsoku":
            guard value.lowercased() == "court" else {
                throw KianIssue(line: lineNumber, message: "kinsoku は court で指定してください。")
            }
            settings.kinsokuMode = "court"
        default:
            issues.append(KianIssue(line: lineNumber, message: "未知の設定「\(key)」は無視しました。", severity: .warning))
        }
    }

    private func points(_ raw: String, line: Int, unitOptional: Bool = false) throws -> CGFloat {
        let lowered = raw.lowercased()
        let numberText: String
        if lowered.hasSuffix("pt") { numberText = String(lowered.dropLast(2)) }
        else if unitOptional { numberText = lowered }
        else { throw KianIssue(line: line, message: "値「\(raw)」にはpt単位が必要です。") }
        guard let value = Double(numberText.trimmingCharacters(in: .whitespaces)), value >= 0 else {
            throw KianIssue(line: line, message: "「\(raw)」は正しいpt値ではありません。")
        }
        return CGFloat(value)
    }

    private func millimeters(_ raw: String, line: Int) throws -> CGFloat {
        let lowered = raw.lowercased()
        guard lowered.hasSuffix("mm"),
              let value = Double(lowered.dropLast(2).trimmingCharacters(in: .whitespaces)),
              value >= 0 else {
            throw KianIssue(line: line, message: "「\(raw)」は正しいmm値ではありません。")
        }
        return CGFloat(value) * KianSettings.pointsPerMillimeter
    }

    private struct CollectionStart {
        var widths: [CGFloat]
        var alignments: [KianColumnAlignment]
        var pureTable: Bool
    }

    private func parseCollectionStart(_ rawLine: String, name: String, line: Int) throws -> CollectionStart {
        let source = rawLine.trimmingCharacters(in: .whitespaces)
        if source.hasSuffix("{") {
            throw KianIssue(line: line, message: "KianPrint2の旧 @\(name) 文法は使用できません。{ } を除き、最終データ行を @end で閉じてください。")
        }
        let prefix = "@\(name)("
        guard source.hasPrefix(prefix), let close = source.firstIndex(of: ")") else {
            throw KianIssue(line: line, message: "@\(name) は @\(name)(6,6)left<Tab>right の形式で指定してください。")
        }
        let argumentStart = source.index(source.startIndex, offsetBy: prefix.count)
        let argument = String(source[argumentStart..<close])
        let tail = String(source[source.index(after: close)...])
        guard !tail.contains("(") && !tail.contains(")") else {
            throw KianIssue(line: line, message: "@\(name) の開始宣言が正しくありません。")
        }

        let components = argument.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == ";" || $0 == "；" }
        )
        guard (1...2).contains(components.count) else {
            throw KianIssue(line: line, message: "@\(name) の列幅指定が正しくありません。")
        }
        let widths = try parsePositiveNumbers(String(components[0]), line: line, description: "列幅")
        var pureTable = false
        if components.count == 2 {
            guard name == "table",
                  components[1].trimmingCharacters(in: .whitespaces).lowercased() == "puretable" else {
                throw KianIssue(line: line, message: "@table のオプションには puretable だけを指定できます。")
            }
            pureTable = true
        }
        let alignments = try normalizedAlignments(from: tail, columnCount: widths.count, line: line)
        return CollectionStart(widths: widths, alignments: alignments, pureTable: pureTable)
    }

    private func parsePositiveNumbers(
        _ raw: String,
        line: Int,
        description: String
    ) throws -> [CGFloat] {
        let values = raw.split { $0 == "," || $0 == "，" || $0 == "、" }
        let numbers = values.compactMap {
            Double($0.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) }
        }
        guard !values.isEmpty, numbers.count == values.count, numbers.allSatisfy({ $0 > 0 }) else {
            throw KianIssue(line: line, message: "\(description)は正の数をカンマ区切りで指定してください。")
        }
        return numbers
    }

    private func normalizedAlignments(from raw: String, columnCount: Int, line: Int) throws -> [KianColumnAlignment] {
        let tokens = raw.isEmpty ? [] : raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        var result = try tokens.map { token -> KianColumnAlignment in
            switch token.lowercased() {
            case "left": return .leading
            case "center": return .center
            case "right": return .trailing
            default:
                throw KianIssue(line: line, message: "配置は left、center、right をTabで区切って指定してください。")
            }
        }
        result = Array(result.prefix(columnCount))
        while result.count < columnCount { result.append(.leading) }
        return result
    }

    private func alignmentDeclaration(_ raw: String, columnCount: Int, line: Int) throws -> [KianColumnAlignment]? {
        let tokens = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard !tokens.isEmpty, tokens.allSatisfy({ ["left", "center", "right"].contains($0.lowercased()) }) else {
            return nil
        }
        return try normalizedAlignments(from: raw, columnCount: columnCount, line: line)
    }

    private func parseNewTable(
        lines: [String],
        start: Int,
        upperBound: Int
    ) throws -> (table: KianTable, nextIndex: Int) {
        let declaration = try parseCollectionStart(lines[start], name: "table", line: start + 1)
        var currentAlignments = declaration.alignments
        var parsedRows: [KianTableRow] = []
        var index = start + 1
        var foundEnd = false

        while index < upperBound {
            let raw = lines[index]
            let endsBlock = raw.hasSuffix("@end")
            let content = endsBlock ? String(raw.dropLast(4)) : raw
            if endsBlock && content.isEmpty {
                throw KianIssue(line: index + 1, message: "@end は独立行にせず、最終データ行の末尾に書いてください。")
            }
            if !parsedRows.isEmpty, let changed = try alignmentDeclaration(content, columnCount: declaration.widths.count, line: index + 1) {
                guard !endsBlock else {
                    throw KianIssue(line: index + 1, message: "@end は配置宣言ではなく最終データ行の末尾に書いてください。")
                }
                currentAlignments = changed
                index += 1
                continue
            }
            let cells = try tableCells(content, columnCount: declaration.widths.count, line: index + 1)
            parsedRows.append(KianTableRow(cells: cells, alignments: currentAlignments, sourceLine: index + 1))
            index += 1
            if endsBlock {
                foundEnd = true
                break
            }
        }
        guard foundEnd else {
            throw KianIssue(line: start + 1, message: "@table の最終データ行を閉じる @end がありません。")
        }
        guard let first = parsedRows.first else {
            throw KianIssue(line: start + 1, message: "@table には少なくとも1行のデータが必要です。")
        }
        return (KianTable(
            headers: first.cells,
            headerAlignments: first.alignments,
            rows: Array(parsedRows.dropFirst()),
            columnWidthsInFontUnits: declaration.widths,
            repeatsHeader: !declaration.pureTable,
            sourceLine: first.sourceLine
        ), index)
    }

    private func parseNewTabbedBlock(
        lines: [String],
        start: Int,
        upperBound: Int
    ) throws -> (block: KianTabbedBlock, nextIndex: Int) {
        let declaration = try parseCollectionStart(lines[start], name: "tab", line: start + 1)
        var currentAlignments = declaration.alignments
        var parsedLines: [KianTabbedLine] = []
        var index = start + 1
        var foundEnd = false

        while index < upperBound {
            let raw = lines[index]
            let endsBlock = raw.hasSuffix("@end")
            let content = endsBlock ? String(raw.dropLast(4)) : raw
            if endsBlock && content.isEmpty {
                throw KianIssue(line: index + 1, message: "@end は独立行にせず、最終データ行の末尾に書いてください。")
            }
            if !parsedLines.isEmpty, let changed = try alignmentDeclaration(content, columnCount: declaration.widths.count, line: index + 1) {
                guard !endsBlock else {
                    throw KianIssue(line: index + 1, message: "@end は配置宣言ではなく最終データ行の末尾に書いてください。")
                }
                currentAlignments = changed
                index += 1
                continue
            }
            let cells = try tabbedCells(content, columnCount: declaration.widths.count, line: index + 1)
            parsedLines.append(KianTabbedLine(cells: cells, alignments: currentAlignments, sourceLine: index + 1))
            index += 1
            if endsBlock {
                foundEnd = true
                break
            }
        }
        guard foundEnd else {
            throw KianIssue(line: start + 1, message: "@tab の最終データ行を閉じる @end がありません。")
        }
        return (KianTabbedBlock(columnWidthsInFontUnits: declaration.widths, lines: parsedLines), index)
    }

    private func tableCells(_ raw: String, columnCount: Int, line: Int) throws -> [KianTableCell] {
        var values = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard values.count <= columnCount else {
            throw KianIssue(line: line, message: "列幅の指定数（\(columnCount)）より内容セルの数（\(values.count)）が多いため、Tabを減らしてください。")
        }
        while values.count < columnCount { values.append("") }
        return values.map { KianTableCell(inlines: parseInline($0)) }
    }

    private func tabbedCells(_ raw: String, columnCount: Int, line: Int) throws -> [[KianInline]] {
        var values = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard values.count <= columnCount else {
            throw KianIssue(line: line, message: "列幅の指定数（\(columnCount)）より内容セルの数（\(values.count)）が多いため、Tabを減らしてください。")
        }
        while values.count < columnCount { values.append("") }
        return values.map(parseInline)
    }

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    private func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = splitTableRow(line)
        return !cells.isEmpty && cells.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private func splitTableRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.first == "|" { text.removeFirst() }
        if text.last == "|" { text.removeLast() }
        var result: [String] = []
        var current = ""
        var escaped = false
        for character in text {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else { current.append(character) }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private struct StyledLine {
        var text: String
        var alignment: KianTextAlignment = .leading
        var fontSize: CGFloat?
        var trailingInset: CGFloat = 0
    }

    private func parseLineStyle(_ raw: String, line: Int) throws -> StyledLine {
        let expression = try! NSRegularExpression(
            pattern: #"@(right|center|size)(?:\(([^()]*)\))?$"#
        )
        var result = StyledLine(text: raw)
        var hasAlignment = false
        var hasSize = false

        while true {
            let range = NSRange(result.text.startIndex..., in: result.text)
            guard let match = expression.firstMatch(in: result.text, range: range),
                  let wholeRange = Range(match.range(at: 0), in: result.text),
                  let nameRange = Range(match.range(at: 1), in: result.text) else { break }
            let name = String(result.text[nameRange])
            let argument: String?
            if match.range(at: 2).location == NSNotFound {
                argument = nil
            } else {
                argument = Range(match.range(at: 2), in: result.text).map { String(result.text[$0]) }
            }

            switch name {
            case "center":
                guard argument == nil else {
                    throw KianIssue(line: line, message: "@center には数値を指定できません。")
                }
                guard !hasAlignment else {
                    throw KianIssue(line: line, message: "@right と @center は同じ行に重ねて指定できません。")
                }
                result.alignment = .center
                hasAlignment = true
            case "right":
                guard !hasAlignment else {
                    throw KianIssue(line: line, message: "@right と @center は同じ行に重ねて指定できません。")
                }
                if let argument {
                    guard let value = Double(argument), value >= 0 else {
                        throw KianIssue(line: line, message: "@right の引数は右側に空けるpt数を0以上の数で指定してください。")
                    }
                    result.trailingInset = CGFloat(value)
                }
                result.alignment = .trailing
                hasAlignment = true
            case "size":
                guard !hasSize else {
                    throw KianIssue(line: line, message: "@size は同じ行に1回だけ指定してください。")
                }
                guard let argument, let value = Double(argument), value > 0 else {
                    throw KianIssue(line: line, message: "@size の引数は絶対フォントサイズを正のpt数で指定してください。")
                }
                result.fontSize = CGFloat(value)
                hasSize = true
            default:
                break
            }
            result.text = String(result.text[..<wholeRange.lowerBound])
        }
        return result
    }

    private func parseInline(_ text: String) -> [KianInline] {
        var result: [KianInline] = []
        var buffer = ""
        var bold = false
        var italic = false
        var index = text.startIndex
        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(KianInline(text: buffer, bold: bold, italic: italic))
            buffer = ""
        }
        while index < text.endIndex {
            if text[index...].hasPrefix("**") {
                flush(); bold.toggle(); index = text.index(index, offsetBy: 2)
            } else if text[index] == "*" {
                flush(); italic.toggle(); index = text.index(after: index)
            } else {
                buffer.append(text[index]); index = text.index(after: index)
            }
        }
        flush()
        if result.isEmpty { result = [KianInline(text: "")] }
        return result
    }

    private func legacyAlignedParagraph(_ line: String, sourceLine: Int) -> KianBlock? {
        let spaces = "　"
        let variants: [(prefix: Int, suffix: Int, alignment: KianTextAlignment, level: Int)] = [
            (5, 5, .center, 1), (4, 4, .center, 2), (3, 3, .center, 3),
            (2, 2, .center, 4), (2, 1, .trailing, 4)
        ]
        for variant in variants {
            if line.hasPrefix(String(repeating: spaces, count: variant.prefix)),
               line.hasSuffix(String(repeating: spaces, count: variant.suffix)) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if variant.alignment == .center {
                    return .heading(KianHeading(level: variant.level, inlines: parseInline(text), sourceLine: sourceLine))
                }
                return .blockBox(KianBlockBox(
                    alignment: .trailing,
                    contentAlignment: .trailing,
                    width: .full,
                    paragraphs: [KianParagraph(inlines: parseInline(text), sourceLine: sourceLine, alignment: .trailing)]
                ))
            }
        }
        return nil
    }
}
