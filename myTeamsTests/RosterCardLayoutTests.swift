//
//  RosterCardLayoutTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// How a roster card is sized and how its name wraps
/// (`PlayerCardLayout`): two lines in the carousel rather than a name cut
/// off mid-word, a width that keeps up with the text at every size, and a
/// list row that grows to fit at accessibility sizes.
@MainActor
@Suite("Roster card layout")
struct RosterCardLayoutTests {
    /// The carousel's text sizes, up to the largest before the roster
    /// becomes a list.
    static let carouselCategories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large,
        .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
    ]

    static let accessibilityCategories: [UIContentSizeCategory] = [
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    /// The name's font at `category`, as the card draws it.
    private func nameFont(at category: UIContentSizeCategory) -> UIFont {
        UIFont.preferredFont(
            forTextStyle: PlayerCardLayout.metricsUITextStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
    }

    private func width(of text: String, in font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: Wrapping

    @Test("In the carousel a name wraps to two lines")
    func carouselWrapsToTwoLines() {
        #expect(PlayerCardLayout.lineLimit(fillsRow: false) == 2)
    }

    @Test("In a list row a name takes as many lines as it needs")
    func listRowIsUnlimited() {
        #expect(PlayerCardLayout.lineLimit(fillsRow: true) == nil)
    }

    @Test("Shrinking is a last resort, and slight")
    func minimumScaleIsSlight() {
        #expect(PlayerCardLayout.minimumScaleFactor >= 0.75)
        #expect(PlayerCardLayout.minimumScaleFactor < 1)
    }

    @Test(
        "A long name breaks between words, each word whole on its line",
        arguments: ["Andrew Armstrong", "Kristian Christensen", "Maximilian Oberhauser"]
    )
    func longNameFitsTwoLines(name: String) {
        let words = name.split(separator: " ").map(String.init)
        #expect(words.count == 2)

        for category in Self.carouselCategories {
            let font = nameFont(at: category)
            let cardWidth = PlayerCardLayout.scaledWidth(for: category)

            // Each word fits a line of its own at full size, so two lines
            // hold the name without cutting into a word or shrinking it.
            for word in words {
                #expect(
                    width(of: word, in: font) <= cardWidth,
                    "\"\(word)\" is wider than the card at \(category.rawValue)"
                )
            }
        }
    }

    // MARK: Scaling

    @Test("The card scales by the text style it draws the name in")
    func scalesByRenderedTextStyle() {
        #expect(PlayerCardLayout.metricsTextStyle == .caption2)
        #expect(PlayerCardLayout.metricsUITextStyle == .caption2)
    }

    @Test("The card's width keeps pace with its text at every size")
    func widthGrowsWithText() {
        let baseFontSize = nameFont(at: .large).pointSize
        var previous: CGFloat = 0

        for category in Self.carouselCategories + Self.accessibilityCategories {
            let width = PlayerCardLayout.scaledWidth(for: category)
            let textRatio = nameFont(at: category).pointSize / baseFontSize

            // Never narrower, for the text in it, than at the default size;
            // allows 2% for the font sizes' rounding.
            #expect(
                width >= PlayerCardLayout.baseWidth * textRatio * 0.98,
                "Card \(width) pt is narrower than the text needs at \(category.rawValue)"
            )
            #expect(width >= previous)
            previous = width
        }
        #expect(abs(PlayerCardLayout.scaledWidth(for: .large) - PlayerCardLayout.baseWidth) < 0.5)
    }

    @Test("The headshot always fits inside the card")
    func headshotFitsCard() {
        #expect(PlayerCardLayout.baseHeadshotSize < PlayerCardLayout.baseWidth)
    }

    // MARK: List rows

    @Test("In the carousel the card has its scaled width")
    func carouselWidth() {
        #expect(PlayerCardLayout.width(scaledWidth: 120, fillsRow: false) == 120)
        #expect(PlayerCardLayout.headshotSize(scaled: 150, fillsRow: false) == 150)
    }

    @Test("In a list row the card spans the row")
    func listRowSpansRow() {
        #expect(PlayerCardLayout.width(scaledWidth: 120, fillsRow: true) == nil)
    }

    @Test("In a list row the headshot is capped, leaving the name room")
    func listRowHeadshotCapped() {
        let scaled = UIFontMetrics(forTextStyle: PlayerCardLayout.metricsUITextStyle).scaledValue(
            for: PlayerCardLayout.baseHeadshotSize,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        let headshot = PlayerCardLayout.headshotSize(scaled: scaled, fillsRow: true)
        #expect(headshot == PlayerCardLayout.maxRowHeadshotSize)
        #expect(PlayerCardLayout.headshotSize(scaled: 40, fillsRow: true) == 40)

        // Beside it on the narrowest current phone (375 pt, less the page's
        // and the list's padding and the row's spacing), a long word still
        // fits a line.
        let textWidth: CGFloat = 375 - 2 * 12 - 2 * 16 - 12 - headshot
        let font = nameFont(at: .accessibilityExtraExtraExtraLarge)
        #expect(width(of: "Armstrong", in: font) <= textWidth)
    }
}
