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

public struct KianSettings: Sendable, Equatable {
    public static let pointsPerMillimeter = 72.0 / 25.4

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
    public var kinsokuMode = "裁判所"

    public init() {}

    public var contentWidth: CGFloat { paperWidth - leftMargin - rightMargin }
    public var contentHeight: CGFloat { paperHeight - topMargin - bottomMargin }
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
    public var paragraphs: [KianParagraph]

    public init(
        alignment: KianTextAlignment,
        contentAlignment: KianTextAlignment,
        width: Width,
        paragraphs: [KianParagraph]
    ) {
        self.alignment = alignment
        self.contentAlignment = contentAlignment
        self.width = width
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

public enum KianTableKind: String, Sendable, Equatable {
    case generic
    case evidenceList
    case evidenceRequest
    case evidenceOpinion
    case attachments
    case parties
}

public struct KianTable: Sendable, Equatable {
    public var headers: [KianTableCell]
    public var alignments: [KianColumnAlignment]
    public var rows: [KianTableRow]
    public var kind: KianTableKind
    public var sourceLine: Int

    public init(
        headers: [KianTableCell],
        alignments: [KianColumnAlignment],
        rows: [KianTableRow],
        kind: KianTableKind = .generic,
        sourceLine: Int
    ) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
        self.kind = kind
        self.sourceLine = sourceLine
    }
}

public struct KianField: Sendable, Equatable {
    public var label: String
    public var value: [KianInline]
    public init(label: String, value: [KianInline]) {
        self.label = label
        self.value = value
    }
}

public enum KianBlock: Sendable, Equatable {
    case paragraph(KianParagraph)
    case heading(KianHeading)
    case quote(KianParagraph)
    case blockBox(KianBlockBox)
    case table(KianTable)
    case caseInfo(fields: [KianField], sourceLine: Int)
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
