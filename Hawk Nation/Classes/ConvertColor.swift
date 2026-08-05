//
//  ConvertColor.swift
//  myTeams
//
//  Created by Stephen Rector on 12/17/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

extension Color {
    /// Builds a colour from the six-digit hex strings the ESPN feeds use for
    /// team colours, with or without a leading `#`.
    ///
    /// Anything that is not a valid hex triple — including the empty string a
    /// summary carries before it has loaded — comes back clear, so a detail
    /// sheet tints to nothing rather than to an arbitrary colour.
    init(hexString: String, opacity: Double = 1) {
        let digits = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("#")

        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .clear
            return
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}
