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
                let presetRows = pairs.filter { $0.key == "プリセット" }
                if let invalid = presetRows.first(where: { $0.value != KianPreset.court.rawValue }) {
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
            recognizer: &recognizer,
            forcedTableKind: nil,
            forcedColumnWidths: nil,
            forcedFirstRowAlignment: nil
        )
        return KianDocument(settings: settings, blocks: blocks, issues: issues)
    }

    private func parseBlocks(
        lines: [String],
        range: Range<Int>,
        recognizer: inout LegalNumberingRecognizer,
        forcedTableKind: KianTableKind?,
        forcedColumnWidths: [CGFloat]?,
        forcedFirstRowAlignment: KianColumnAlignment?
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
            if ["@改ページ", "[改ページ]", "【改ページ】"].contains(trimmed) {
                blocks.append(.pageBreak)
                index += 1
                continue
            }

            if let directive = directiveStart(trimmed) {
                guard directive.name != "改ページ" else {
                    blocks.append(.pageBreak)
                    index += 1
                    continue
                }
                let bodyStart = index + 1
                var end = bodyStart
                while end < range.upperBound, lines[end].trimmingCharacters(in: .whitespaces) != "}" {
                    end += 1
                }
                guard end < range.upperBound else {
                    throw KianIssue(line: index + 1, message: "@\(directive.name) を閉じる } がありません。")
                }
                let bodyRange = bodyStart..<end
                switch directive.name {
                case "右揃え", "中央揃え", "右配置":
                    let trailingInset = try rightAlignmentInset(
                        directive.argument,
                        directiveName: directive.name,
                        line: index + 1
                    )
                    let paragraphs = bodyRange.map { bodyIndex -> KianParagraph in
                        let indent = recognizer.indent(for: lines[bodyIndex])
                        return KianParagraph(
                            inlines: parseInline(lines[bodyIndex].trimmingCharacters(in: .whitespaces)),
                            sourceLine: bodyIndex + 1,
                            indentLevel: indent.level,
                            firstLineOutdent: indent.outdent,
                            alignment: directive.name == "中央揃え" ? .center : (directive.name == "右揃え" ? .trailing : .leading)
                        )
                    }
                    let box = KianBlockBox(
                        alignment: directive.name == "中央揃え" ? .center : .trailing,
                        contentAlignment: directive.name == "右配置" ? .leading : (directive.name == "中央揃え" ? .center : .trailing),
                        width: directive.name == "右配置"
                            ? .fit(maximumFraction: trailingInset > 0 ? 1 : 0.58)
                            : .full,
                        trailingInset: trailingInset,
                        paragraphs: paragraphs
                    )
                    blocks.append(.blockBox(box))
                case "表", "罫線なし表":
                    let kind: KianTableKind = directive.name == "罫線なし表" ? .borderless : .generic
                    let options = try parseTableOptions(
                        directive.argument,
                        directiveName: directive.name,
                        line: index + 1
                    )
                    let inner = try parseBlocks(
                        lines: lines,
                        range: bodyRange,
                        recognizer: &recognizer,
                        forcedTableKind: kind,
                        forcedColumnWidths: options.columnWidths,
                        forcedFirstRowAlignment: options.firstRowAlignment
                    )
                    blocks.append(contentsOf: inner)
                case "タブ":
                    let tabStops = try parseTabStops(directive.argument, line: index + 1)
                    let tabbedLines = try bodyRange.map { bodyIndex in
                        let cells = lines[bodyIndex].split(separator: "\t", omittingEmptySubsequences: false).map {
                            parseInline($0.trimmingCharacters(in: .whitespaces))
                        }
                        guard cells.count <= tabStops.count + 1 else {
                            throw KianIssue(line: bodyIndex + 1, message: "指定したタブ位置より多くのTab文字があります。")
                        }
                        return KianTabbedLine(cells: cells, sourceLine: bodyIndex + 1)
                    }
                    blocks.append(.tabbed(KianTabbedBlock(tabStopsInCharacters: tabStops, lines: tabbedLines)))
                default:
                    throw KianIssue(line: index + 1, message: "未知のDirective @\(directive.name) です。")
                }
                index = end + 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 4, trimmed.dropFirst(hashes).first == " " {
                    let title = String(trimmed.dropFirst(hashes + 1))
                    blocks.append(.heading(KianHeading(level: hashes, inlines: parseInline(title), sourceLine: index + 1)))
                    index += 1
                    continue
                }
            }

            if index + 1 < range.upperBound,
               isTableRow(line),
               isTableSeparator(lines[index + 1]) {
                let parsed = try parseTable(
                    lines: lines,
                    start: index,
                    upperBound: range.upperBound,
                    forcedKind: forcedTableKind,
                    forcedColumnWidths: forcedColumnWidths,
                    forcedFirstRowAlignment: forcedFirstRowAlignment
                )
                blocks.append(.table(parsed.table))
                index = parsed.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(KianParagraph(inlines: parseInline(content), sourceLine: index + 1, indentLevel: 1)))
                index += 1
                continue
            }

            if let legacy = legacyAlignedParagraph(line, sourceLine: index + 1) {
                blocks.append(legacy)
                index += 1
                continue
            }

            let indent = recognizer.indent(for: line)
            blocks.append(.paragraph(KianParagraph(
                inlines: parseInline(line),
                sourceLine: index + 1,
                indentLevel: indent.level,
                firstLineOutdent: indent.outdent
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
        case "プリセット":
            guard value == KianPreset.court.rawValue else {
                throw KianIssue(line: lineNumber, message: "未知のプリセット「\(value)」です。")
            }
            settings = KianSettings()
        case "用紙":
            guard value.uppercased() == "A4" else {
                throw KianIssue(line: lineNumber, message: "β版で使用できる用紙はA4だけです。")
            }
        case "フォント": settings.fontName = value
        case "文字サイズ": settings.fontSize = try points(value, line: lineNumber)
        case "上余白": settings.topMargin = try millimeters(value, line: lineNumber)
        case "下余白": settings.bottomMargin = try millimeters(value, line: lineNumber)
        case "左余白": settings.leftMargin = try millimeters(value, line: lineNumber)
        case "右余白": settings.rightMargin = try millimeters(value, line: lineNumber)
        case "行間": settings.lineSpacing = try points(value, line: lineNumber)
        case "字間": settings.characterSpacing = try points(value, line: lineNumber, unitOptional: true)
        case "ページ番号":
            if ["あり", "有り", "on", "yes", "true"].contains(value.lowercased()) { settings.showsPageNumbers = true }
            else if ["なし", "無し", "off", "no", "false"].contains(value.lowercased()) { settings.showsPageNumbers = false }
            else { throw KianIssue(line: lineNumber, message: "ページ番号は「あり」または「なし」で指定してください。") }
        case "禁則処理": settings.kinsokuMode = value
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

    private func rightAlignmentInset(
        _ argument: String?,
        directiveName: String,
        line: Int
    ) throws -> CGFloat {
        guard let argument else { return 0 }
        guard directiveName != "中央揃え" else {
            throw KianIssue(line: line, message: "@中央揃えには引数を指定できません。")
        }
        guard let value = Double(argument.trimmingCharacters(in: .whitespaces)), value >= 0 else {
            throw KianIssue(
                line: line,
                message: "@\(directiveName) の引数は「3」のように、12pt文字何字分を空けるか指定してください。"
            )
        }
        return CGFloat(value) * 12
    }

    private struct TableOptions {
        var columnWidths: [CGFloat]?
        var firstRowAlignment: KianColumnAlignment?
    }

    private func parseTableOptions(
        _ argument: String?,
        directiveName: String,
        line: Int
    ) throws -> TableOptions {
        guard let argument else { return TableOptions() }
        var result = TableOptions()
        let components = argument.split(whereSeparator: { $0 == ";" || $0 == "；" })
        for rawComponent in components {
            let component = rawComponent.trimmingCharacters(in: .whitespaces)
            let widthPrefixes = ["列幅=", "列幅＝", "列幅:", "列幅："]
            if let prefix = widthPrefixes.first(where: { component.hasPrefix($0) }) {
                result.columnWidths = try parsePositiveNumbers(
                    String(component.dropFirst(prefix.count)),
                    line: line,
                    description: "列幅"
                )
            } else if ["先頭行=中央", "先頭行＝中央", "先頭行:中央", "先頭行：中央"].contains(component) {
                result.firstRowAlignment = .center
            } else {
                throw KianIssue(
                    line: line,
                    message: "@\(directiveName) の引数は「列幅=4,8,3; 先頭行=中央」の形式で指定してください。"
                )
            }
        }
        return result
    }

    private func parseTabStops(_ argument: String?, line: Int) throws -> [CGFloat] {
        guard let argument else {
            throw KianIssue(line: line, message: "@タブには「@タブ(11,21)」のようにタブ位置を指定してください。")
        }
        let stops = try parsePositiveNumbers(argument, line: line, description: "タブ位置")
        guard zip(stops, stops.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else {
            throw KianIssue(line: line, message: "タブ位置は左から小さい順に指定してください。")
        }
        return stops
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

    private func directiveStart(_ line: String) -> (name: String, argument: String?)? {
        guard line.hasPrefix("@") else { return nil }
        if line == "@改ページ" { return ("改ページ", nil) }
        guard line.hasSuffix("{") else { return nil }
        let head = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        if let open = head.firstIndex(of: "("), head.hasSuffix(")") {
            return (String(head[..<open]), String(head[head.index(after: open)..<head.index(before: head.endIndex)]))
        }
        return (head, nil)
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

    private func parseTable(
        lines: [String],
        start: Int,
        upperBound: Int,
        forcedKind: KianTableKind?,
        forcedColumnWidths: [CGFloat]?,
        forcedFirstRowAlignment: KianColumnAlignment?
    ) throws -> (table: KianTable, nextIndex: Int) {
        let headerStrings = splitTableRow(lines[start])
        if let forcedColumnWidths, forcedColumnWidths.count != headerStrings.count {
            throw KianIssue(
                line: start + 1,
                message: "列幅の指定数（\(forcedColumnWidths.count)）と表の列数（\(headerStrings.count)）が一致しません。"
            )
        }
        let separators = splitTableRow(lines[start + 1])
        let alignments: [KianColumnAlignment] = separators.map {
            let value = $0.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix(":") && value.hasSuffix(":") { return .center }
            if value.hasSuffix(":") { return .trailing }
            return .leading
        }
        var rows: [KianTableRow] = []
        var index = start + 2
        while index < upperBound, isTableRow(lines[index]) {
            var cells = splitTableRow(lines[index]).map { KianTableCell(inlines: parseInline($0)) }
            while cells.count < headerStrings.count { cells.append(KianTableCell(inlines: [])) }
            if cells.count > headerStrings.count { cells = Array(cells.prefix(headerStrings.count)) }
            rows.append(KianTableRow(cells: cells, sourceLine: index + 1))
            index += 1
        }
        let headers = headerStrings.map { KianTableCell(inlines: parseInline($0)) }
        let kind = forcedKind ?? .generic
        return (KianTable(
            headers: headers,
            alignments: alignments,
            rows: rows,
            kind: kind,
            columnWidthsInCharacters: forcedColumnWidths,
            firstRowAlignment: forcedFirstRowAlignment,
            sourceLine: start + 1
        ), index)
    }

    private func parseInline(_ text: String) -> [KianInline] {
        let text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
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
