//
//  RosterCardLayoutTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/5/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// How a roster card is sized and how its caption wraps
/// (`PlayerCardLayout`): two lines in the carousel rather than a name cut
/// off mid-word, a width that keeps up with the text at every size, a list
/// row that grows to fit at accessibility sizes, and the initials drawn
/// where there's no headshot.
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

    /// The caption's font at `category`, as the card draws it.
    private func captionFont(at category: UIContentSizeCategory) -> UIFont {
        UIFont.preferredFont(
            forTextStyle: PlayerCardLayout.metricsUITextStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
    }

    private func width(of text: String, in font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The pieces a line may break between: words, and a hyphenated word
    /// after its hyphen ("Anudike-", "Uzomah").
    private func segments(of name: String) -> [String] {
        name.split(separator: " ").flatMap { word -> [String] in
            let parts = word.split(separator: "-", omittingEmptySubsequences: false)
            return parts.enumerated().map { index, part in
                index < parts.count - 1 ? "\(part)-" : String(part)
            }
        }
    }

    // MARK: Wrapping

    @Test("In the carousel a caption wraps to two lines")
    func carouselWrapsToTwoLines() {
        #expect(PlayerCardLayout.lineLimit(fillsRow: false) == 2)
    }

    @Test("In a list row a caption takes as many lines as it needs")
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
        arguments: ["Andrew Armstrong", "Kristian Christensen", "Maximilian Oberhauser", "Felix Anudike-Uzomah"]
    )
    func longNameFitsTwoLines(name: String) {
        let pieces = segments(of: name)

        for category in Self.carouselCategories {
            let font = captionFont(at: category)
            let captionWidth = PlayerCardLayout.scaledWidth(for: category)

            // Each piece fits a line of its own at full size, so two lines
            // hold the name without cutting into a word or shrinking it.
            for piece in pieces {
                #expect(
                    width(of: piece, in: font) <= captionWidth,
                    "\"\(piece)\" is wider than the caption at \(category.rawValue)"
                )
            }
        }
    }

    @Test("A hyphenated surname fits whole at the default size")
    func hyphenatedSurnameFitsWhole() {
        let font = captionFont(at: .large)
        #expect(width(of: "Anudike-Uzomah", in: font) <= PlayerCardLayout.baseWidth)
    }

    @Test("Every sort shares the caption's style, with \"N/A\" for a blank field (B-17)")
    func captionText() {
        #expect(PlayerCardLayout.caption("Felix Anudike-Uzomah") == "Felix Anudike-Uzomah")
        #expect(PlayerCardLayout.caption("") == "N/A")
        #expect(PlayerCardLayout.caption("  ") == "N/A")
    }

    // MARK: Scaling

    @Test("The card scales by the text style it draws the caption in")
    func scalesByRenderedTextStyle() {
        #expect(PlayerCardLayout.metricsTextStyle == .caption2)
        #expect(PlayerCardLayout.metricsUITextStyle == .caption2)
    }

    @Test("The caption's width keeps pace with its text at every size")
    func widthGrowsWithText() {
        let baseFontSize = captionFont(at: .large).pointSize
        var previous: CGFloat = 0

        for category in Self.carouselCategories + Self.accessibilityCategories {
            let width = PlayerCardLayout.scaledWidth(for: category)
            let textRatio = captionFont(at: category).pointSize / baseFontSize

            // Never narrower, for the text in it, than at the default size;
            // allows 2% for the font sizes' rounding.
            #expect(
                width >= PlayerCardLayout.baseWidth * textRatio * 0.98,
                "Caption \(width) pt is narrower than the text needs at \(category.rawValue)"
            )
            #expect(width >= previous)
            previous = width
        }
        #expect(abs(PlayerCardLayout.scaledWidth(for: .large) - PlayerCardLayout.baseWidth) < 0.5)
    }

    @Test("The headshot is no wider than the caption under it")
    func headshotFitsCard() {
        #expect(PlayerCardLayout.baseHeadshotSize < PlayerCardLayout.baseWidth)
    }

    // MARK: List rows

    @Test("In the carousel the caption has its scaled width")
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
    }

    // MARK: Initials

    @Test("Initials are the first and last names' first letters")
    func initials() {
        #expect(PlayerCardLayout.initials(of: "Felix Anudike-Uzomah") == "FA")
        #expect(PlayerCardLayout.initials(of: "Travis Kelce") == "TK")
        #expect(PlayerCardLayout.initials(of: "neymar") == "N")
        #expect(PlayerCardLayout.initials(of: "  ") == "")
    }
}
