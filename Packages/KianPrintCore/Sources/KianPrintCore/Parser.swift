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
            recognizer: &recognizer,
            forcedColumnWidths: nil,
            forcedFirstRowAlignment: nil
        )
        return KianDocument(settings: settings, blocks: blocks, issues: issues)
    }

    private func parseBlocks(
        lines: [String],
        range: Range<Int>,
        recognizer: inout LegalNumberingRecognizer,
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
            if trimmed == "@page" {
                blocks.append(.pageBreak)
                index += 1
                continue
            }

            if let directive = directiveStart(trimmed) {
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
                case "table":
                    let options = try parseTableOptions(
                        directive.argument,
                        directiveName: directive.name,
                        line: index + 1
                    )
                    let inner = try parseBlocks(
                        lines: lines,
                        range: bodyRange,
                        recognizer: &recognizer,
                        forcedColumnWidths: options.columnWidths,
                        forcedFirstRowAlignment: options.firstRowAlignment
                    )
                    blocks.append(contentsOf: inner)
                case "tab":
                    let tabIntervals = try parseTabIntervals(directive.argument, line: index + 1)
                    let tabbedLines = try bodyRange.map { bodyIndex in
                        let cells = lines[bodyIndex].split(separator: "\t", omittingEmptySubsequences: false).map {
                            parseInline(String($0))
                        }
                        guard cells.count <= tabIntervals.count + 1 else {
                            throw KianIssue(line: bodyIndex + 1, message: "指定したタブ間隔の個数より多くのTab文字があります。")
                        }
                        return KianTabbedLine(cells: cells, sourceLine: bodyIndex + 1)
                    }
                    blocks.append(.tabbed(KianTabbedBlock(tabIntervalsInFontUnits: tabIntervals, lines: tabbedLines)))
                default:
                    throw KianIssue(line: index + 1, message: "未知のDirective @\(directive.name) です。")
                }
                index = end + 1
                continue
            }

            if trimmed.hasPrefix("@") {
                throw KianIssue(line: index + 1, message: "未知のDirective \(trimmed) です。")
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
        let components = argument.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == ";" || $0 == "；" }
        )
        guard (1...2).contains(components.count) else {
            throw KianIssue(line: line, message: "@\(directiveName) は @table(4,8,3; center) の形式で指定してください。")
        }
        var result = TableOptions()
        result.columnWidths = try parsePositiveNumbers(
            String(components[0]),
            line: line,
            description: "column widths"
        )
        if components.count == 2 {
            switch components[1].trimmingCharacters(in: .whitespaces).lowercased() {
            case "center": result.firstRowAlignment = .center
            case "right": result.firstRowAlignment = .trailing
            default:
                throw KianIssue(line: line, message: "先頭行の配置は center または right で指定してください。")
            }
        }
        return result
    }

    private func parseTabIntervals(_ argument: String?, line: Int) throws -> [CGFloat] {
        guard let argument else {
            throw KianIssue(line: line, message: "@tab には @tab(4,6) のように前のタブ位置からの間隔を指定してください。")
        }
        return try parsePositiveNumbers(argument, line: line, description: "タブ間隔")
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
        return (KianTable(
            headers: headers,
            alignments: alignments,
            rows: rows,
            columnWidthsInFontUnits: forcedColumnWidths,
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
