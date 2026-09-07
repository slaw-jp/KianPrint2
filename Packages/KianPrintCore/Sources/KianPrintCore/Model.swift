import CoreGraphics
import Foundation

public enum KianIssueSeverity: Sendable {
    case warning
    case error
}

public struct KianIssue: Error, Sendable, Equatable, CustomStringConvertible {
    public var line: Int?
    public var message: String
    public var severity: KianIssueSeverity

    public init(line: Int? = nil, message: String, severity: KianIssueSeverity = .error) {
        self.line = line
        self.message = message
        self.severity = severity
    }

    public var description: String {
        if let line { return "\(line)行目: \(message)" }
        return message
    }
}

public enum KianTextAlignment: String, Sendable {
    case leading
    case center
    case trailing
}

public enum KianPreset: String, Sendable, Equatable {
    case court
}

public struct KianSettings: Sendable, Equatable {
    public static let pointsPerMillimeter = 72.0 / 25.4
    public static let courtColumns = 37
    public static let courtLinesPerPage = 26

    public var paperWidth: CGFloat = 210 * pointsPerMillimeter
    public var paperHeight: CGFloat = 297 * pointsPerMillimeter
    public var fontName = "Hiragino Mincho ProN W3"
    public var fontSize: CGFloat = 12
    public var topMargin: CGFloat = 35 * pointsPerMillimeter
    public var bottomMargin: CGFloat = 27 * pointsPerMillimeter
    public var leftMargin: CGFloat = 30 * pointsPerMillimeter
    public var rightMargin: CGFloat = 22 * pointsPerMillimeter
    /// Extra leading after a 12 pt line, matching legacy KianPrint's 13.62 pt setting.
    public var lineSpacing: CGFloat = 13.62
    public var characterSpacing: CGFloat = 0
    public var showsPageNumbers = true
    public var kinsokuMode = "court"
    /// `court` means the source had no settings, or explicitly selected the
    /// court preset. `nil` means that a manual front matter block is in use.
    public var preset: KianPreset? = .court

    public init() {}

    public var contentWidth: CGFloat { paperWidth - leftMargin - rightMargin }
    public var contentHeight: CGFloat { paperHeight - topMargin - bottomMargin }

    /// The legacy Court Style values form a fixed 37-column by 26-line grid.
    /// Customized typography or geometry falls back to measured free layout.
    public var usesStandardCourtGrid: Bool {
        preset == .court
    }

    public var paragraphContentWidth: CGFloat {
        guard usesStandardCourtGrid else { return contentWidth }
        // Keep the legacy margin-derived slack used by halfwidth glyphs and
        // punctuation, while ensuring that a 38th fullwidth glyph never fits.
        return min(contentWidth, CGFloat(Self.courtColumns + 1) * fontSize - 0.001)
    }

    public var lineAdvance: CGFloat {
        usesStandardCourtGrid ? contentHeight / CGFloat(Self.courtLinesPerPage) : fontSize + lineSpacing
    }
}

public struct KianInline: Sendable, Equatable {
    public var text: String
    public var bold: Bool
    public var italic: Bool

    public init(text: String, bold: Bool = false, italic: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
    }
}

public struct KianParagraph: Sendable, Equatable {
    public var inlines: [KianInline]
    public var sourceLine: Int
    public var indentLevel: Int
    public var firstLineOutdent: Int
    public var alignment: KianTextAlignment

    public init(
        inlines: [KianInline],
        sourceLine: Int,
        indentLevel: Int = 0,
        firstLineOutdent: Int = 0,
        alignment: KianTextAlignment = .leading
    ) {
        self.inlines = inlines
        self.sourceLine = sourceLine
        self.indentLevel = indentLevel
        self.firstLineOutdent = firstLineOutdent
        self.alignment = alignment
    }

    public var plainText: String { inlines.map(\.text).joined() }
}

public struct KianHeading: Sendable, Equatable {
    public var level: Int
    public var inlines: [KianInline]
    public var sourceLine: Int

    public init(level: Int, inlines: [KianInline], sourceLine: Int) {
        self.level = level
        self.inlines = inlines
        self.sourceLine = sourceLine
    }

    public var plainText: String { inlines.map(\.text).joined() }
}

public struct KianBlockBox: Sendable, Equatable {
    public enum Width: Sendable, Equatable { case full, fit(maximumFraction: CGFloat) }
    public var alignment: KianTextAlignment
    public var contentAlignment: KianTextAlignment
    public var width: Width
    /// Space kept clear at the right edge of the text frame, for example for a seal.
    public var trailingInset: CGFloat
    public var paragraphs: [KianParagraph]

    public init(
        alignment: KianTextAlignment,
        contentAlignment: KianTextAlignment,
        width: Width,
        trailingInset: CGFloat = 0,
        paragraphs: [KianParagraph]
    ) {
        self.alignment = alignment
        self.contentAlignment = contentAlignment
        self.width = width
        self.trailingInset = trailingInset
        self.paragraphs = paragraphs
    }
}

public enum KianColumnAlignment: Sendable, Equatable {
    case leading, center, trailing
}

public struct KianTableCell: Sendable, Equatable {
    public var inlines: [KianInline]
    public init(inlines: [KianInline]) { self.inlines = inlines }
    public var plainText: String { inlines.map(\.text).joined() }
}

public struct KianTableRow: Sendable, Equatable {
    public var cells: [KianTableCell]
    public var sourceLine: Int
    public init(cells: [KianTableCell], sourceLine: Int) {
        self.cells = cells
        self.sourceLine = sourceLine
    }
}

public struct KianTable: Sendable, Equatable {
    public var headers: [KianTableCell]
    public var alignments: [KianColumnAlignment]
    public var rows: [KianTableRow]
    /// Absolute column widths, measured in 12pt fullwidth-character units.
    public var columnWidthsInCharacters: [CGFloat]?
    public var firstRowAlignment: KianColumnAlignment?
    public var sourceLine: Int

    public init(
        headers: [KianTableCell],
        alignments: [KianColumnAlignment],
        rows: [KianTableRow],
        columnWidthsInCharacters: [CGFloat]? = nil,
        firstRowAlignment: KianColumnAlignment? = nil,
        sourceLine: Int
    ) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
        self.columnWidthsInCharacters = columnWidthsInCharacters
        self.firstRowAlignment = firstRowAlignment
        self.sourceLine = sourceLine
    }
}

public struct KianTabbedLine: Sendable, Equatable {
    public var cells: [[KianInline]]
    public var sourceLine: Int

    public init(cells: [[KianInline]], sourceLine: Int) {
        self.cells = cells
        self.sourceLine = sourceLine
    }
}

public struct KianTabbedBlock: Sendable, Equatable {
    /// Distances from the preceding tab stop, measured in document-font-size units.
    public var tabIntervalsInFontUnits: [CGFloat]
    public var lines: [KianTabbedLine]

    public init(tabIntervalsInFontUnits: [CGFloat], lines: [KianTabbedLine]) {
        self.tabIntervalsInFontUnits = tabIntervalsInFontUnits
        self.lines = lines
    }
}

public enum KianBlock: Sendable, Equatable {
    case paragraph(KianParagraph)
    case heading(KianHeading)
    case quote(KianParagraph)
    case blockBox(KianBlockBox)
    case table(KianTable)
    case tabbed(KianTabbedBlock)
    case pageBreak
    case spacer(CGFloat)
}

public struct KianDocument: Sendable, Equatable {
    public var settings: KianSettings
    public var blocks: [KianBlock]
    public var issues: [KianIssue]

    public init(settings: KianSettings, blocks: [KianBlock], issues: [KianIssue] = []) {
        self.settings = settings
        self.blocks = blocks
        self.issues = issues
    }
}
