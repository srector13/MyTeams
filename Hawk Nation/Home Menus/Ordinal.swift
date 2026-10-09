//
//  Ordinal.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// Shared by the app (alerts, schedule cards, standings) and the widget
// extension (the Live Activity's stage). Compiled into both targets.

/// "1st", "2nd", "3rd", "4th", … "11th", "12th", "13th", "21st".
func ordinalString(_ number: Int) -> String {
    let suffix: String
    switch (number % 10, number % 100) {
    case (_, 11...13): suffix = "th"
    case (1, _): suffix = "st"
    case (2, _): suffix = "nd"
    case (3, _): suffix = "rd"
    default: suffix = "th"
    }
    return "\(number)\(suffix)"
}
