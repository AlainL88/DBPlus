//
//  SQLTextEditor.swift
//  DB+
//
//  Editor SQL con autocompletamento:
//    - macOS: NSTextView con evidenziazione sintattica MySQL/MariaDB e
//      completion nativa (F5 / popup automatico).
//    - iOS/iPadOS: UITextView con barra di suggerimenti sopra la tastiera.
//
//  I candidati (keyword SQL + tabelle/viste/schemi) vengono forniti dal
//  chiamante tramite `completionCandidates`.
//

import SwiftUI

/// Parole chiave SQL suggerite in fase di digitazione.
enum SQLCompletion {
    static let keywords: [String] = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "INDEX", "PRIMARY", "KEY",
        "FOREIGN", "REFERENCES", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER",
        "FULL", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "AS",
        "AND", "OR", "NOT", "NULL", "IS", "IN", "LIKE", "BETWEEN", "EXISTS",
        "CASE", "WHEN", "THEN", "ELSE", "END", "DISTINCT", "COUNT", "SUM", "AVG",
        "MIN", "MAX", "UNION", "ALL", "EXPLAIN", "DESCRIBE", "SHOW", "USE",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "CONSTRAINT", "DEFAULT",
        "AUTO_INCREMENT", "UNIQUE", "VIEW", "PROCEDURE", "FUNCTION", "TRIGGER",
        "DATABASE", "SCHEMA", "GRANT", "REVOKE", "COMMENT", "ADD", "RENAME",
        "MODIFY", "CHANGE", "ENGINE", "COLLATE", "CHARSET", "CASCADE",
    ]
}

/// Caratteri che compongono un identificatore (lettere, cifre, underscore).
private func isWordCharacter(_ c: unichar) -> Bool {
    guard let scalar = UnicodeScalar(c) else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    return allowed.contains(scalar)
}

#if os(macOS)

import AppKit

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var completionCandidates: [String] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = context.coordinator

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.textStorage?.setAttributedString(SQLHighlighter.highlight(text))
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLTextEditor
        private var highlightPending = false

        init(_ parent: SQLTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlight(textView)
            maybeTriggerCompletion(textView)
        }

        func textView(_ textView: NSTextView,
                      completions words: [String],
                      forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard !parent.completionCandidates.isEmpty else { return words }
            let partial = (textView.string as NSString).substring(with: charRange)
            let lower = partial.lowercased()
            let filtered = parent.completionCandidates
                .filter { $0.lowercased().hasPrefix(lower) && $0.caseInsensitiveCompare(partial) != .orderedSame }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            index?.pointee = 0
            return Array(filtered.prefix(50))
        }

        private func scheduleHighlight(_ textView: NSTextView) {
            if highlightPending { return }
            highlightPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak textView] in
                self?.highlightPending = false
                guard let self, let textView else { return }
                let selectedRange = textView.selectedRange()
                textView.textStorage?.setAttributedString(SQLHighlighter.highlight(textView.string))
                textView.setSelectedRange(selectedRange)
            }
        }

        private func maybeTriggerCompletion(_ textView: NSTextView) {
            guard !parent.completionCandidates.isEmpty else { return }
            let location = textView.selectedRange().location
            let partial = partialWord(at: location, in: textView.string)
            guard partial.count >= 2 else { return }
            let lower = partial.lowercased()
            let hasMatches = parent.completionCandidates.contains {
                $0.lowercased().hasPrefix(lower) && $0.caseInsensitiveCompare(partial) != .orderedSame
            }
            if hasMatches {
                textView.complete(nil)
            }
        }

        private func partialWord(at location: Int, in string: String) -> String {
            let ns = string as NSString
            var start = location
            while start > 0, isWordCharacter(ns.character(at: start - 1)) {
                start -= 1
            }
            return ns.substring(with: NSRange(location: start, length: location - start))
        }
    }
}

#else

import UIKit

struct SQLTextEditor: UIViewRepresentable {
    @Binding var text: String
    var completionCandidates: [String] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.inputAccessoryView = context.coordinator.accessoryBar
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SQLTextEditor
        let accessoryBar = UIStackView()

        init(_ parent: SQLTextEditor) {
            self.parent = parent
            accessoryBar.axis = .horizontal
            accessoryBar.spacing = 8
            accessoryBar.alignment = .center
            accessoryBar.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            accessoryBar.isLayoutMarginsRelativeArrangement = true
            accessoryBar.backgroundColor = .secondarySystemBackground
            accessoryBar.frame = CGRect(x: 0, y: 0, width: 400, height: 44)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateSuggestions(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSuggestions(textView)
        }

        private func updateSuggestions(_ textView: UITextView) {
            accessoryBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
            guard !parent.completionCandidates.isEmpty else { return }

            let location = textView.selectedRange.location
            let (partial, range) = partialWord(at: location, in: textView.text)
            guard !partial.isEmpty, range.length > 0 else { return }

            let lower = partial.lowercased()
            let matches = parent.completionCandidates
                .filter { $0.lowercased().hasPrefix(lower) && $0.caseInsensitiveCompare(partial) != .orderedSame }
                .prefix(5)

            guard !matches.isEmpty else { return }

            let label = UILabel()
            label.text = partial
            label.font = .systemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabel
            label.setContentHuggingPriority(.required, for: .horizontal)
            accessoryBar.addArrangedSubview(label)

            for match in matches {
                let button = UIButton(type: .system)
                button.setTitle(match, for: .normal)
                button.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                button.addAction(UIAction { [weak self, weak textView] _ in
                    guard let self, let textView else { return }
                    self.insert(match, replacing: range, in: textView)
                }, for: .touchUpInside)
                accessoryBar.addArrangedSubview(button)
            }
        }

        private func insert(_ token: String, replacing range: NSRange, in textView: UITextView) {
            let ns = textView.text as NSString
            guard range.location + range.length <= ns.length else { return }
            let replacement = token + " "
            let newText = ns.replacingCharacters(in: range, with: replacement)
            textView.text = newText
            parent.text = newText
            textView.selectedRange = NSRange(location: range.location + replacement.count, length: 0)
            updateSuggestions(textView)
        }

        private func partialWord(at location: Int, in string: String) -> (String, NSRange) {
            let ns = string as NSString
            var start = location
            while start > 0, isWordCharacter(ns.character(at: start - 1)) {
                start -= 1
            }
            let range = NSRange(location: start, length: location - start)
            return (ns.substring(with: range), range)
        }
    }
}

#endif
