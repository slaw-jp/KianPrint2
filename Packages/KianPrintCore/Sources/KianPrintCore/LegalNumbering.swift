import Foundation

public struct KianIndent: Sendable, Equatable {
    public var level: Int
    public var outdent: Int
    public init(level: Int, outdent: Int) {
        self.level = level
        self.outdent = outdent
    }
}

/// Reimplementation of the numbering hierarchy measured from legacy KianPrint.
public struct LegalNumberingRecognizer {
    private var priorIndents: [Int] = []
    private var priorLines: [String] = []
    private var documentUsesArticles = false

    public init(allLines: [String]) {
        documentUsesArticles = allLines.contains {
            $0.range(of: #"^第[０-９]+[条　]"#, options: .regularExpression) != nil
        }
    }

    public mutating func indent(for line: String) -> KianIndent {
        defer { priorLines.append(line) }
        let adjustment = documentUsesArticles ? 0 : -1
        let patterns: [(String, Int, Int)] = [
            (#"^第[０-９]+条"#, 2, 2),
            (#"^第[０-９]+　"#, 2, 2),
            (#"^[０-９]+　"#, 2, 1),
            (#"^[０-９]+\([0-9]+\)　"#, 3, 2),
            (#"^\([0-9]+\)　"#, 3, 1),
            (#"^\([0-9]+\)[ア-ン]　"#, 4, 2),
            (#"^[ア-ン]　"#, 4, 1),
            (#"^[ア-ン]\([ア-ン]\)　"#, 5, 2),
            (#"^\([ア-ン]\)　"#, 5, 1),
            (#"^\([ア-ン]\)[ａ-ｚ]　"#, 6, 2),
            (#"^[ａ-ｚ]　"#, 6, 1),
            (#"^[ａ-ｚ]\([a-z]\)　"#, 7, 2),
            (#"^\([a-z]\)　"#, 7, 1)
        ]
        for (pattern, level, outdent) in patterns where matches(line, pattern) {
            let value = max(0, level + adjustment)
            priorIndents.append(value)
            return KianIndent(level: value, outdent: outdent)
        }

        if matches(line, #"^[①-⑳]　"#) {
            let value: Int
            if priorLines.last.map({ matches($0, #"^[①-⑳]　"#) }) == true {
                value = priorIndents.last ?? 1
            } else {
                value = (priorIndents.last ?? 0) + 1
            }
            priorIndents.append(value)
            return KianIndent(level: value, outdent: 1)
        }

        if line.hasPrefix("　　") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            var value = priorIndents.last ?? 1
            if priorLines.last.map({ matches($0, #"^[①-⑳]　"#) }) == true {
                value = 1
                for index in priorLines.indices.reversed() where !matches(priorLines[index], #"^[①-⑳]　"#) {
                    value = priorIndents[index]
                    break
                }
            } else if value < 1 {
                value = 1
            }
            priorIndents.append(value)
            return KianIndent(level: value, outdent: 1)
        }

        priorIndents.append(0)
        return KianIndent(level: 0, outdent: 0)
    }

    private func matches(_ line: String, _ pattern: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }
}
