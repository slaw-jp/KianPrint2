import CoreGraphics
import Foundation

public struct KianPlacedText {
    public var text: NSAttributedString
    public var origin: CGPoint
    public var width: CGFloat
    public var ascent: CGFloat
    public var descent: CGFloat

    public init(text: NSAttributedString, origin: CGPoint, width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        self.text = text
        self.origin = origin
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }
}

public enum KianStrokeWeight: Sendable {
    case thin
    case thick
}

public enum KianDrawCommand {
    case text(KianPlacedText)
    case line(from: CGPoint, to: CGPoint, weight: KianStrokeWeight)
    case rectangle(CGRect, weight: KianStrokeWeight)
}

public struct KianPage {
    public var number: Int
    public var size: CGSize
    public var commands: [KianDrawCommand]

    public init(number: Int, size: CGSize, commands: [KianDrawCommand] = []) {
        self.number = number
        self.size = size
        self.commands = commands
    }
}

public struct KianLayout {
    public var settings: KianSettings
    public var pages: [KianPage]

    public init(settings: KianSettings, pages: [KianPage]) {
        self.settings = settings
        self.pages = pages
    }
}
