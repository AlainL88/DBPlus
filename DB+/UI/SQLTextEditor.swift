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
    /// Statement più comuni mostrati prima ancora di digitare, quando il
    /// cursore non è dentro una parola (barra dei suggerimenti su iOS).
    static let starters: [String] = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER",
        "DROP", "SHOW", "EXPLAIN", "USE",
    ]

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

// MARK: - Contesto di completamento

/// Contesto del cursore: cosa ci si aspetta di digitare qui.
enum CompletionContext: Sendable {
    case start   // inizio query → statement
    case table   // dopo FROM/JOIN/UPDATE/… → nome tabella
    case column  // dopo SELECT/WHERE/ON/… → colonna o keyword
}

/// Clausole dopo le quali ci si aspetta un nome di tabella.
private let tableContextKeywords: Set<String> = [
    "FROM", "INTO", "UPDATE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL",
    "TABLE", "REFERENCES", "SHOW", "DESCRIBE", "EXPLAIN",
]

/// Clausole dopo le quali ci si aspetta una colonna (o keyword).
private let columnContextKeywords: Set<String> = [
    "SELECT", "WHERE", "ON", "AND", "OR", "SET", "GROUP", "ORDER", "HAVING",
    "BY", "VALUES", "VALUE", "AS", "BETWEEN", "LIKE", "IN", "IS", "NOT",
]

/// Determina il contesto di completamento dal testo prima del cursore.
private func completionContext(before text: String) -> CompletionContext {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .start }
    let words = trimmed.split(whereSeparator: {
        $0 == " " || $0 == "," || $0 == "(" || $0 == ")" || $0 == "\n" || $0 == "\t"
    })
    guard let last = words.last?.uppercased() else { return .start }
    if tableContextKeywords.contains(last) { return .table }
    if columnContextKeywords.contains(last) { return .column }
    return .column
}

/// Contesto di completamento nel testo, escludendo la parola parziale al cursore.
func completionContext(in text: String, at partialStart: Int) -> CompletionContext {
    let ns = text as NSString
    let before = ns.substring(to: min(partialStart, ns.length))
    return completionContext(before: before)
}

/// Pool di candidati per il prefix match, coerente col contesto.
func completionPool(_ context: CompletionContext,
                    keywords: [String], tables: [String], columns: [String]) -> [String] {
    switch context {
    case .start: return keywords
    case .table: return tables
    case .column: return columns + keywords
    }
}

/// Suggerimenti proattivi quando il cursore non è dentro una parola.
func proactiveSuggestions(_ context: CompletionContext,
                          tables: [String], columns: [String]) -> [String] {
    switch context {
    case .start:
        return SQLCompletion.starters
    case .table:
        return Array(tables.prefix(8))
    case .column:
        return Array(columns.prefix(6)) + ["FROM", "WHERE", "AND", "OR", "ORDER BY", "GROUP BY", "LIMIT"]
    }
}

#if os(macOS)

import AppKit

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var completionKeywords: [String] = []
    var completionTables: [String] = []
    var completionColumns: [String] = []

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
        // Sincronizza il Coordinator con la struct aggiornata: senza questo
        // parent.completionCandidates resterebbe vuota (copia iniziale).
        context.coordinator.parent = self
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
            // Pool di candidati coerente col contesto della query.
            let context = completionContext(in: textView.string, at: charRange.location)
            let pool = completionPool(context,
                                      keywords: parent.completionKeywords,
                                      tables: parent.completionTables,
                                      columns: parent.completionColumns)
            guard !pool.isEmpty else { return words }
            let partial = (textView.string as NSString).substring(with: charRange)
            let lower = partial.lowercased()
            let filtered = pool
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
            let location = textView.selectedRange().location
            let partial = partialWord(at: location, in: textView.string)
            guard partial.count >= 2 else { return }
            let context = completionContext(in: textView.string, at: location - partial.count)
            let pool = completionPool(context,
                                      keywords: parent.completionKeywords,
                                      tables: parent.completionTables,
                                      columns: parent.completionColumns)
            guard !pool.isEmpty else { return }
            let lower = partial.lowercased()
            let hasMatches = pool.contains {
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
    var completionKeywords: [String] = []
    var completionTables: [String] = []
    var completionColumns: [String] = []

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
        // Trascinando verso il basso nell'editor la tastiera si chiude.
        textView.keyboardDismissMode = .interactive
        textView.inputAccessoryView = context.coordinator.accessoryBar
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Sincronizza il Coordinator con la struct aggiornata (in particolare
        // completionCandidates): senza questo i suggerimenti non arrivano mai.
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
            context.coordinator.updateSuggestions(uiView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SQLTextEditor
        let accessoryBar: UIView
        weak var textView: UITextView?
        private let scrollView = UIScrollView()
        private let stack = UIStackView()
        private let partialLabel = UILabel()

        init(_ parent: SQLTextEditor) {
            self.parent = parent

            // Etichetta con la parola parziale corrente.
            partialLabel.font = .systemFont(ofSize: 11, weight: .regular)
            partialLabel.textColor = .secondaryLabel
            partialLabel.setContentHuggingPriority(.required, for: .horizontal)
            partialLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            stack.axis = .horizontal
            stack.spacing = 8
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false

            // Scroll orizzontale: i suggerimenti possono essere più larghi
            // dello schermo e su iPhone non devono mai debordare/tagliarsi.
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.addSubview(stack)

            let container = UIView()
            container.backgroundColor = .secondarySystemBackground
            container.addSubview(scrollView)

            // Pulsante per chiudere la tastiera, sempre visibile a destra.
            // (L'azione viene collegata a fine init, quando self è inizializzato.)
            let dismissButton = UIButton(type: .system)
            dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
            dismissButton.tintColor = .secondaryLabel
            dismissButton.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(dismissButton)

            // Separatore superiore per distinguere la barra dall'editor.
            let hairline = UIView()
            hairline.backgroundColor = .separator
            hairline.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hairline)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
                scrollView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                scrollView.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),

                stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
                // Con pochi suggerimenti lo stack riempie comunque la larghezza.
                stack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),

                dismissButton.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -8),
                dismissButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                dismissButton.widthAnchor.constraint(equalToConstant: 36),
                dismissButton.heightAnchor.constraint(equalToConstant: 36),

                hairline.topAnchor.constraint(equalTo: container.topAnchor),
                hairline.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hairline.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hairline.heightAnchor.constraint(equalToConstant: 1),
            ])

            // La larghezza viene sovrascritta da UIKit con quella della tastiera.
            container.frame = CGRect(x: 0, y: 0, width: 320, height: 48)
            self.accessoryBar = container
            super.init()

            dismissButton.addAction(UIAction { [weak self] _ in
                self?.textView?.resignFirstResponder()
            }, for: .touchUpInside)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateSuggestions(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSuggestions(textView)
        }

        func updateSuggestions(_ textView: UITextView) {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

            let location = textView.selectedRange.location
            let (partial, range) = partialWord(at: location, in: textView.text)

            // Contesto della query per suggerimenti coerenti: all'inizio →
            // statement, dopo FROM/JOIN → tabelle, dopo SELECT/WHERE → colonne.
            let context = completionContext(in: textView.text, at: range.location)
            let keywords = parent.completionKeywords
            let tables = parent.completionTables
            let columns = parent.completionColumns

            // Suggerimenti "intelligenti": prima di digitare mostra le opzioni
            // coerenti con quello che stai scrivendo, non keyword a caso.
            let matches: [String]
            if partial.isEmpty {
                matches = proactiveSuggestions(context, tables: tables, columns: columns)
            } else {
                let lower = partial.lowercased()
                matches = completionPool(context, keywords: keywords, tables: tables, columns: columns)
                    .filter { $0.lowercased().hasPrefix(lower) && $0.caseInsensitiveCompare(partial) != .orderedSame }
                    .prefix(8)
                    .map { $0 }
            }
            guard !matches.isEmpty else { return }

            if !partial.isEmpty {
                partialLabel.text = partial
                stack.addArrangedSubview(partialLabel)
            }

            for match in matches {
                var config = UIButton.Configuration.bordered()
                config.cornerStyle = .capsule
                config.title = match
                config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
                let button = UIButton(configuration: config)
                button.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                button.addAction(UIAction { [weak self, weak textView] _ in
                    guard let self, let textView else { return }
                    self.insert(match, replacing: range, in: textView)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
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
