//
//  PlatformColor.swift
//  DB+
//
//  Colori semantici cross-piattaforma (macOS / iOS / iPadOS).
//  Evita l'uso diretto di NSColor (macOS) e UIColor (iOS) nei ViewBuilder.
//

import SwiftUI

extension Color {

    /// Sfondo della griglia dati.
    static var gridBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Sfondo della riga selezionata.
    static var selectedRowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Sfondo "sotto la pagina" per gli header dei risultati.
    static var underPageBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Linea separatrice.
    static var separatorLine: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    /// Sfondo delle card (superficie chiara sopra uno sfondo raggruppato).
    static var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Sfondo raggruppato (grigio) dietro le card.
    static var groupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
