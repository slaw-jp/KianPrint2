import CoreGraphics
import Foundation

public struct KianLayoutEngine {
    public init() {}

    public func layout(_ document: KianDocument) -> KianLayout {
        let builder = LayoutBuilder(settings: document.settings)
        builder.layout(blocks: document.blocks)
        builder.finishPageNumbers()
        return KianLayout(settings: document.settings, pages: builder.pages)
    }
}

private final class LayoutBuilder {
    let settings: KianSettings
    let breaker = KianLineBreaker()
    var pages: [KianPage] = []
    var cursorY: CGFloat
    var currentPageIndex = 0
    var contentBottom: CGFloat { settings.paperHeight - settings.bottomMargin }
    var baseAdvance: CGFloat { settings.lineAdvance }

    init(settings: KianSettings) {
        self.settings = settings
        cursorY = settings.topMargin
        pages = [KianPage(number: 1, size: CGSize(width: settings.paperWidth, height: settings.paperHeight))]
    }

    func layout(blocks: [KianBlock]) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph): layoutParagraph(paragraph)
            case .quote(var paragraph):
                paragraph.indentLevel += 1
                layoutParagraph(paragraph)
            case .heading(let heading): layoutHeading(heading)
            case .blockBox(let box): layoutBlockBox(box)
            case .table(let table): layoutTable(table)
            case .caseInfo(let fields, _): layoutCaseInfo(fields)
            case .pageBreak: newPage(force: true)
            case .spacer(let spacing): addVerticalSpace(baseAdvance + spacing)
            }
        }
    }

    func finishPageNumbers() {
        guard settings.showsPageNumbers, pages.count > 1 else { return }
        let fontSize = max(8, settings.fontSize - 1)
        for index in pages.indices {
            let attributed = KianTypography.attributedString(
                from: [KianInline(text: "\(index + 1)")], settings: settings, fontSize: fontSize
            )
            let measured = breaker.breakLines(attributed, width: settings.contentWidth)[0]
            let x = settings.leftMargin + (settings.contentWidth - measured.width) / 2
            let textHeight = measured.ascent + measured.descent
            let y = settings.paperHeight - settings.bottomMargin / 2 - textHeight / 2
            pages[index].commands.append(.text(KianPlacedText(
                text: measured.attributedText,
                origin: CGPoint(x: x, y: y),
                width: measured.width,
                ascent: measured.ascent,
                descent: measured.descent
            )))
        }
    }

    private func layoutParagraph(_ paragraph: KianParagraph) {
        let unit = settings.fontSize
        let leadingX = settings.leftMargin + CGFloat(paragraph.indentLevel) * unit
        let firstX = max(settings.leftMargin, leadingX - CGFloat(paragraph.firstLineOutdent) * unit)
        let attributed = KianTypography.attributedString(from: paragraph.inlines, settings: settings)
        let firstWidth = settings.paragraphContentWidth - (firstX - settings.leftMargin)
        let subsequentWidth = settings.paragraphContentWidth - (leadingX - settings.leftMargin)
        let lines = breaker.breakLines(
            attributed,
            firstLineWidth: firstWidth,
            subsequentLineWidth: subsequentWidth
        )
        for (index, line) in lines.enumerated() {
            ensureSpace(baseAdvance)
            let baseX = index == 0 ? firstX : leadingX
            let available = index == 0 ? firstWidth : subsequentWidth
            append(line, x: alignedX(base: baseX, available: available, width: line.width, alignment: paragraph.alignment), y: cursorY)
            cursorY += baseAdvance
        }
    }

    private func layoutHeading(_ heading: KianHeading) {
        // These are the exact ratios used by the original KianPrint:
        // 18/12, 16/12, 14/12 and 12/12 of the document's base size.
        let ratios: [Int: CGFloat] = [1: 18 / 12, 2: 16 / 12, 3: 14 / 12, 4: 1]
        let size = settings.fontSize * (ratios[heading.level] ?? 1)
        // A heading uses a larger glyph size, but still occupies one normal
        // document line.  Its effective leading is therefore reduced so that
        // headings do not lower the page capacity from 26 lines to 25.
        let advance = settings.usesStandardCourtGrid ? baseAdvance : size + settings.lineSpacing
        if contentBottom - cursorY < advance + baseAdvance { newPage(force: false) }
        let attributed = KianTypography.attributedString(
            from: heading.inlines, settings: settings, fontSize: size, forceBold: false
        )
        let lines = breaker.breakLines(attributed, width: settings.contentWidth)
        for line in lines {
            ensureSpace(advance)
            let x = settings.leftMargin + (settings.contentWidth - line.width) / 2
            append(line, x: x, y: cursorY)
            cursorY += advance
        }
    }

    private func layoutBlockBox(_ box: KianBlockBox) {
        let availableContentWidth = max(1, settings.contentWidth - box.trailingInset)
        let blockWidth: CGFloat
        switch box.width {
        case .full: blockWidth = availableContentWidth
        case .fit(let maximumFraction):
            let preferred = box.paragraphs.map {
                KianTypography.width(of: KianTypography.attributedString(from: $0.inlines, settings: settings))
            }.max() ?? 0
            blockWidth = min(availableContentWidth * maximumFraction, max(availableContentWidth * 0.25, preferred))
        }
        let originX: CGFloat
        switch box.alignment {
        case .leading: originX = settings.leftMargin
        case .center: originX = settings.leftMargin + (availableContentWidth - blockWidth) / 2
        case .trailing: originX = settings.leftMargin + availableContentWidth - blockWidth
        }
        for paragraph in box.paragraphs {
            let attributed = KianTypography.attributedString(from: paragraph.inlines, settings: settings)
            for line in breaker.breakLines(attributed, width: blockWidth) {
                ensureSpace(baseAdvance)
                let x = alignedX(base: originX, available: blockWidth, width: line.width, alignment: box.contentAlignment)
                append(line, x: x, y: cursorY)
                cursorY += baseAdvance
            }
        }
    }

    private func layoutCaseInfo(_ fields: [KianField]) {
        let visibleLabels = fields.filter { $0.label != "事件名" }
        let labelWidth = visibleLabels.map {
            KianTypography.width(of: KianTypography.attributedString(from: [KianInline(text: $0.label)], settings: settings))
        }.max() ?? 0
        let gap = settings.fontSize * 2
        for field in fields {
            if field.label == "事件名" {
                addVerticalSpace(baseAdvance * 0.35)
                let paragraph = KianParagraph(inlines: field.value, sourceLine: 0)
                layoutParagraph(paragraph)
                addVerticalSpace(baseAdvance * 0.35)
                continue
            }
            let label = KianTypography.attributedString(from: [KianInline(text: field.label)], settings: settings)
            let value = KianTypography.attributedString(from: field.value, settings: settings)
            let valueX = settings.leftMargin + labelWidth + gap
            let valueWidth = settings.paperWidth - settings.rightMargin - valueX
            let valueLines = breaker.breakLines(value, width: valueWidth)
            let rowHeight = max(baseAdvance, CGFloat(valueLines.count) * baseAdvance)
            ensureSpace(rowHeight)
            append(breaker.breakLines(label, width: labelWidth).first!, x: settings.leftMargin, y: cursorY)
            for (offset, line) in valueLines.enumerated() {
                append(line, x: valueX, y: cursorY + CGFloat(offset) * baseAdvance)
            }
            cursorY += rowHeight
        }
    }

    private func layoutTable(_ table: KianTable) {
        switch table.kind {
        case .evidenceRequest: layoutRecordTable(table, bordered: true)
        case .parties: layoutParties(table)
        case .attachments: layoutAttachments(table)
        case .generic, .evidenceList, .evidenceOpinion: layoutGridTable(table)
        }
    }

    private func layoutGridTable(_ table: KianTable) {
        guard !table.headers.isEmpty else { return }
        let widths = columnWidths(for: table)
        let boldHeader = table.kind == .generic
        let headerHeight = tableRowHeight(cells: table.headers, widths: widths, bold: boldHeader)
        let firstRowHeight = table.rows.first.map { tableRowHeight(cells: $0.cells, widths: widths, bold: false) } ?? 0
        ensureSpace(headerHeight + firstRowHeight)
        drawGridRow(cells: table.headers, widths: widths, height: headerHeight, alignments: table.alignments, bold: boldHeader, topWeight: .thin)

        var priorGroup = ""
        for row in table.rows {
            let height = tableRowHeight(cells: row.cells, widths: widths, bold: false)
            if contentBottom - cursorY < height {
                newPage(force: false)
                drawGridRow(cells: table.headers, widths: widths, height: headerHeight, alignments: table.alignments, bold: boldHeader, topWeight: .thin)
            }
            var topWeight: KianStrokeWeight = .thin
            if table.kind == .evidenceOpinion, let group = row.cells.first?.plainText, !group.isEmpty {
                if !priorGroup.isEmpty, group != priorGroup { topWeight = .thick }
                priorGroup = group
            }
            drawGridRow(cells: row.cells, widths: widths, height: height, alignments: table.alignments, bold: false, topWeight: topWeight)
        }
    }

    private func drawGridRow(
        cells: [KianTableCell],
        widths: [CGFloat],
        height: CGFloat,
        alignments: [KianColumnAlignment],
        bold: Bool,
        topWeight: KianStrokeWeight
    ) {
        let top = cursorY
        var x = settings.leftMargin
        pages[currentPageIndex].commands.append(.line(from: CGPoint(x: x, y: top), to: CGPoint(x: x + widths.reduce(0, +), y: top), weight: topWeight))
        for index in widths.indices {
            pages[currentPageIndex].commands.append(.line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: top + height), weight: .thin))
            let cell = index < cells.count ? cells[index] : KianTableCell(inlines: [])
            let attributed = KianTypography.attributedString(from: cell.inlines, settings: settings, fontSize: settings.fontSize - 1, forceBold: bold)
            let padding: CGFloat = 4
            let lines = breaker.breakLines(attributed, width: max(1, widths[index] - padding * 2))
            let alignment = index < alignments.count ? alignments[index] : .leading
            for (offset, line) in lines.enumerated() {
                let lineX: CGFloat
                switch alignment {
                case .leading: lineX = x + padding
                case .center: lineX = x + (widths[index] - line.width) / 2
                case .trailing: lineX = x + widths[index] - padding - line.width
                }
                append(line, x: lineX, y: top + padding + CGFloat(offset) * (settings.fontSize + 4))
            }
            x += widths[index]
        }
        pages[currentPageIndex].commands.append(.line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: top + height), weight: .thin))
        pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin, y: top + height), to: CGPoint(x: x, y: top + height), weight: .thin))
        cursorY += height
    }

    private func tableRowHeight(cells: [KianTableCell], widths: [CGFloat], bold: Bool) -> CGFloat {
        let heights = widths.indices.map { index -> CGFloat in
            let cell = index < cells.count ? cells[index] : KianTableCell(inlines: [])
            let attributed = KianTypography.attributedString(from: cell.inlines, settings: settings, fontSize: settings.fontSize - 1, forceBold: bold)
            let count = breaker.breakLines(attributed, width: max(1, widths[index] - 8)).count
            return CGFloat(max(1, count)) * (settings.fontSize + 4) + 8
        }
        return heights.max() ?? baseAdvance
    }

    private func columnWidths(for table: KianTable) -> [CGFloat] {
        let count = table.headers.count
        let preset: [CGFloat]?
        switch table.kind {
        case .evidenceList:
            // 符号番号／標目／原本・写し／作成年月日／作成者／立証趣旨
            // follows the proportions of the author's filed evidence lists.
            preset = count == 6 ? [0.10, 0.29, 0.05, 0.15, 0.15, 0.26] : nil
        case .evidenceOpinion:
            preset = count == 4 ? [0.12, 0.46, 0.15, 0.27] : nil
        default: preset = nil
        }
        if let preset { return preset.map { $0 * settings.contentWidth } }

        var preferred = Array(repeating: CGFloat(36), count: count)
        let allRows = [table.headers] + table.rows.map(\.cells)
        for row in allRows {
            for index in 0..<min(count, row.count) {
                let width = KianTypography.width(of: KianTypography.attributedString(from: row[index].inlines, settings: settings, fontSize: settings.fontSize - 1)) + 10
                preferred[index] = min(settings.contentWidth * 0.45, max(preferred[index], width))
            }
        }
        let total = preferred.reduce(0, +)
        if total == 0 { return Array(repeating: settings.contentWidth / CGFloat(count), count: count) }
        return preferred.map { $0 / total * settings.contentWidth }
    }

    private func layoutAttachments(_ table: KianTable) {
        let widths = [settings.fontSize * 3, settings.contentWidth - settings.fontSize * 10, settings.fontSize * 7]
        for row in table.rows {
            let height = tableRowHeight(cells: row.cells, widths: widths, bold: false) - 8
            ensureSpace(height)
            var x = settings.leftMargin
            for index in 0..<min(3, row.cells.count) {
                let attributed = KianTypography.attributedString(from: row.cells[index].inlines, settings: settings)
                let lines = breaker.breakLines(attributed, width: widths[index])
                for (offset, line) in lines.enumerated() {
                    let alignment: KianTextAlignment = index == 1 ? .leading : .trailing
                    append(line, x: alignedX(base: x, available: widths[index], width: line.width, alignment: alignment), y: cursorY + CGFloat(offset) * baseAdvance)
                }
                x += widths[index]
            }
            cursorY += max(baseAdvance, height)
        }
    }

    private func layoutParties(_ table: KianTable) {
        let addressIndex = table.headers.firstIndex { $0.plainText == "住所" } ?? 1
        let nameIndex = table.headers.firstIndex { $0.plainText == "氏名・名称" } ?? 2
        let noteIndex = table.headers.firstIndex { $0.plainText == "補足" }
        let roleX = settings.leftMargin + settings.fontSize * 4
        let nameX = roleX + settings.fontSize * 10
        let nameWidth = max(settings.fontSize, settings.paperWidth - settings.rightMargin - nameX)

        for row in table.rows {
            let role = row.cells.first?.inlines ?? []
            let address = addressIndex < row.cells.count ? row.cells[addressIndex].inlines : []
            let name = nameIndex < row.cells.count ? row.cells[nameIndex].inlines : []
            let note = noteIndex.flatMap { $0 < row.cells.count ? row.cells[$0].inlines : nil } ?? []

            let addressLines = breaker.breakLines(
                KianTypography.attributedString(from: address, settings: settings),
                width: settings.contentWidth
            )
            let nameLines = breaker.breakLines(
                KianTypography.attributedString(from: name, settings: settings),
                width: nameWidth
            )
            let noteLines = note.map(\.text).joined().isEmpty ? [] : breaker.breakLines(
                KianTypography.attributedString(from: note, settings: settings),
                width: settings.paperWidth - settings.rightMargin - roleX
            )
            let requiredLines = addressLines.count + max(1, nameLines.count) + noteLines.count
            ensureSpace(CGFloat(requiredLines) * baseAdvance)

            for line in addressLines {
                append(line, x: settings.leftMargin, y: cursorY)
                cursorY += baseAdvance
            }
            let roleLine = breaker.breakLines(
                KianTypography.attributedString(from: role, settings: settings),
                width: settings.fontSize * 10
            ).first
            if let roleLine { append(roleLine, x: roleX, y: cursorY) }
            for (offset, line) in nameLines.enumerated() {
                append(line, x: nameX, y: cursorY + CGFloat(offset) * baseAdvance)
            }
            cursorY += CGFloat(max(1, nameLines.count)) * baseAdvance
            for line in noteLines {
                append(line, x: roleX, y: cursorY)
                cursorY += baseAdvance
            }
            addVerticalSpace(baseAdvance * 0.5)
        }
    }

    private func layoutRecordTable(_ table: KianTable, bordered: Bool) {
        guard !table.headers.isEmpty else { return }
        let labelWidth = min(settings.contentWidth * 0.27, table.headers.dropFirst().map {
            KianTypography.width(of: KianTypography.attributedString(from: $0.inlines, settings: settings, forceBold: true)) + 12
        }.max() ?? settings.contentWidth * 0.22)
        let valueWidth = settings.contentWidth - labelWidth

        for row in table.rows {
            var heights: [CGFloat] = []
            let titleLines = breaker.breakLines(KianTypography.attributedString(from: row.cells.first?.inlines ?? [], settings: settings, forceBold: true), width: settings.contentWidth - 8)
            heights.append(CGFloat(max(1, titleLines.count)) * baseAdvance + 8)
            for index in 1..<table.headers.count {
                let cell = index < row.cells.count ? row.cells[index] : KianTableCell(inlines: [])
                let lines = breaker.breakLines(KianTypography.attributedString(from: cell.inlines, settings: settings), width: valueWidth - 8)
                heights.append(CGFloat(max(1, lines.count)) * baseAdvance + 8)
            }
            let recordHeight = heights.reduce(0, +)
            if recordHeight <= settings.contentHeight, contentBottom - cursorY < recordHeight { newPage(force: false) }
            let recordTop = cursorY

            for (offset, line) in titleLines.enumerated() {
                append(line, x: settings.leftMargin + 4, y: cursorY + 4 + CGFloat(offset) * baseAdvance)
            }
            cursorY += heights[0]
            if bordered {
                pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin, y: cursorY), to: CGPoint(x: settings.leftMargin + settings.contentWidth, y: cursorY), weight: .thin))
            }
            for index in 1..<table.headers.count {
                let rowHeight = heights[index]
                if contentBottom - cursorY < rowHeight { newPage(force: false) }
                let label = KianTypography.attributedString(from: table.headers[index].inlines, settings: settings, forceBold: true)
                let cell = index < row.cells.count ? row.cells[index] : KianTableCell(inlines: [])
                let values = breaker.breakLines(KianTypography.attributedString(from: cell.inlines, settings: settings), width: valueWidth - 8)
                append(breaker.breakLines(label, width: labelWidth - 8).first!, x: settings.leftMargin + 4, y: cursorY + 4)
                for (offset, line) in values.enumerated() {
                    append(line, x: settings.leftMargin + labelWidth + 4, y: cursorY + 4 + CGFloat(offset) * baseAdvance)
                }
                if bordered {
                    pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin, y: cursorY + rowHeight), to: CGPoint(x: settings.leftMargin + settings.contentWidth, y: cursorY + rowHeight), weight: .thin))
                    pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin + labelWidth, y: cursorY), to: CGPoint(x: settings.leftMargin + labelWidth, y: cursorY + rowHeight), weight: .thin))
                }
                cursorY += rowHeight
            }
            if bordered, currentPageIndex == pages.count - 1 {
                pages[currentPageIndex].commands.append(.rectangle(CGRect(x: settings.leftMargin, y: recordTop, width: settings.contentWidth, height: cursorY - recordTop), weight: .thin))
                pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin, y: recordTop), to: CGPoint(x: settings.leftMargin + settings.contentWidth, y: recordTop), weight: .thick))
            } else if !bordered {
                addVerticalSpace(baseAdvance * 0.5)
            }
        }
    }

    private func alignedX(base: CGFloat, available: CGFloat, width: CGFloat, alignment: KianTextAlignment) -> CGFloat {
        switch alignment {
        case .leading: return base
        case .center: return base + (available - width) / 2
        case .trailing: return base + available - width
        }
    }

    private func append(_ line: KianMeasuredLine, x: CGFloat, y: CGFloat) {
        pages[currentPageIndex].commands.append(.text(KianPlacedText(
            text: line.attributedText,
            origin: CGPoint(x: x, y: y),
            width: line.width,
            ascent: line.ascent,
            descent: line.descent
        )))
    }

    private func addVerticalSpace(_ amount: CGFloat) {
        guard cursorY > settings.topMargin + 0.5 else { return }
        if cursorY + amount > contentBottom { newPage(force: false) }
        else { cursorY += amount }
    }

    private func ensureSpace(_ amount: CGFloat) {
        if cursorY + amount > contentBottom { newPage(force: false) }
    }

    private func newPage(force: Bool) {
        if !force, cursorY <= settings.topMargin + 0.5 { return }
        if force, cursorY <= settings.topMargin + 0.5, pages[currentPageIndex].commands.isEmpty { return }
        currentPageIndex += 1
        pages.append(KianPage(number: currentPageIndex + 1, size: CGSize(width: settings.paperWidth, height: settings.paperHeight)))
        cursorY = settings.topMargin
    }
}
