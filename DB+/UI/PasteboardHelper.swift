//
//  PasteboardHelper.swift
//  DB+
//

import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PasteboardHelper {
    /// Copia testo nella clipboard di sistema (UIPasteboard / NSPasteboard).
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}
