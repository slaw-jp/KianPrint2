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
            case .tabbed(let block): layoutTabbedBlock(block)
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

    private func layoutTable(_ table: KianTable) {
        layoutGridTable(table)
    }

    private func layoutGridTable(_ table: KianTable) {
        guard !table.headers.isEmpty else { return }
        let widths = columnWidths(for: table)
        let boldHeader = false
        let headerAlignments = table.firstRowAlignment.map {
            Array(repeating: $0, count: table.headers.count)
        } ?? table.alignments
        let headerHeight = tableRowHeight(cells: table.headers, widths: widths, bold: boldHeader)
        let firstRowHeight = table.rows.first.map { tableRowHeight(cells: $0.cells, widths: widths, bold: false) } ?? 0
        ensureSpace(headerHeight + firstRowHeight)
        drawGridRow(cells: table.headers, widths: widths, height: headerHeight, alignments: headerAlignments, bold: boldHeader, topWeight: .thin)

        for row in table.rows {
            let height = tableRowHeight(cells: row.cells, widths: widths, bold: false)
            if contentBottom - cursorY < height {
                newPage(force: false)
                drawGridRow(cells: table.headers, widths: widths, height: headerHeight, alignments: headerAlignments, bold: boldHeader, topWeight: .thin)
            }
            drawGridRow(cells: row.cells, widths: widths, height: height, alignments: table.alignments, bold: false, topWeight: .thin)
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
            let verticalPadding: CGFloat = 4
            let horizontalPadding: CGFloat = 3
            let lines = breaker.breakLines(attributed, width: max(1, widths[index] - horizontalPadding * 2))
            let alignment = index < alignments.count ? alignments[index] : .leading
            for (offset, line) in lines.enumerated() {
                let lineX: CGFloat
                switch alignment {
                case .leading: lineX = x + horizontalPadding
                case .center: lineX = x + (widths[index] - line.width) / 2
                case .trailing: lineX = x + widths[index] - horizontalPadding - line.width
                }
                append(line, x: lineX, y: top + verticalPadding + CGFloat(offset) * (settings.fontSize + 4))
            }
            x += widths[index]
        }
        pages[currentPageIndex].commands.append(.line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: top + height), weight: .thin))
        pages[currentPageIndex].commands.append(.line(from: CGPoint(x: settings.leftMargin, y: top + height), to: CGPoint(x: x, y: top + height), weight: .thin))
        cursorY += height
    }

    private func tableRowHeight(cells: [KianTableCell], widths: [CGFloat], bold: Bool) -> CGFloat {
        let horizontalPadding: CGFloat = 3
        let heights = widths.indices.map { index -> CGFloat in
            let cell = index < cells.count ? cells[index] : KianTableCell(inlines: [])
            let attributed = KianTypography.attributedString(from: cell.inlines, settings: settings, fontSize: settings.fontSize - 1, forceBold: bold)
            let count = breaker.breakLines(attributed, width: max(1, widths[index] - horizontalPadding * 2)).count
            return CGFloat(max(1, count)) * (settings.fontSize + 4) + 8
        }
        return heights.max() ?? baseAdvance
    }

    private func columnWidths(for table: KianTable) -> [CGFloat] {
        let count = table.headers.count
        guard count > 0 else { return [] }
        if let widths = table.columnWidthsInFontUnits, widths.count == count {
            return widths.map { $0 * settings.fontSize }
        }

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

    private func layoutTabbedBlock(_ block: KianTabbedBlock) {
        var cumulativeOffset: CGFloat = 0
        let tabStops = block.tabIntervalsInFontUnits.map { interval -> CGFloat in
            cumulativeOffset += interval * settings.fontSize
            return cumulativeOffset
        }
        for row in block.lines {
            let measuredCells = row.cells.enumerated().map { index, inlines -> [KianMeasuredLine] in
                let xOffset = index == 0 ? 0 : tabStops[index - 1]
                let nextOffset = index == row.cells.count - 1 ? settings.contentWidth : tabStops[index]
                let width = max(1, nextOffset - xOffset)
                let attributed = KianTypography.attributedString(from: inlines, settings: settings)
                return breakTabbedCell(attributed, width: width)
            }
            let rowHeight = CGFloat(max(1, measuredCells.map(\.count).max() ?? 1)) * baseAdvance
            ensureSpace(rowHeight)
            for (index, lines) in measuredCells.enumerated() {
                let xOffset = index == 0 ? 0 : tabStops[index - 1]
                for (lineIndex, line) in lines.enumerated() {
                    append(
                        line,
                        x: settings.leftMargin + xOffset,
                        y: cursorY + CGFloat(lineIndex) * baseAdvance
                    )
                }
            }
            cursorY += rowHeight
        }
    }

    private func breakTabbedCell(_ attributed: NSAttributedString, width: CGFloat) -> [KianMeasuredLine] {
        let lines = breaker.breakLines(attributed, width: width)
        guard !attributed.string.contains("\n"),
              lines.count >= 2,
              lines[lines.count - 1].attributedText.string.count == 1 else {
            return lines
        }

        let previousIndex = lines.count - 2
        let previous = lines[previousIndex].attributedText
        let previousString = previous.string as NSString
        guard previousString.length >= 2 else { return lines }
        let movedRange = previousString.rangeOfComposedCharacterSequence(at: previousString.length - 1)
        guard movedRange.location > 0 else { return lines }

        let shortened = previous.attributedSubstring(
            from: NSRange(location: 0, length: movedRange.location)
        )
        let combined = NSMutableAttributedString(
            attributedString: previous.attributedSubstring(from: movedRange)
        )
        combined.append(lines[lines.count - 1].attributedText)

        let shortenedLines = breaker.breakLines(shortened, width: width)
        let combinedLines = breaker.breakLines(combined, width: width)
        guard shortenedLines.count == 1, combinedLines.count == 1 else { return lines }

        var adjusted = lines
        adjusted[previousIndex] = shortenedLines[0]
        adjusted[previousIndex + 1] = combinedLines[0]
        return adjusted
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
