//
//  BrandIconStyle.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The reader's style of the myTeams mark: the shape drawn wherever the
/// logo appears in the app (`BrandLogoMark`, the team bar's crest), in the
/// brand accent's colour or gradient (`BrandAccent.fill`). Stored in
/// `UserDefaults` under `storageKey` and applied to the whole app at the
/// root (`MyTeamsApp`, `View.brandIconStyle(_:)`), like `BrandAccent`.
///
/// The two choices are independent: any style in any accent.
///
/// `classic` is the shipped logo and changes nothing: with the shipped blue
/// it is the original full-colour art, and with another accent the arches
/// take the accent over the T's bars, as `BrandAccent` draws them.
///
/// The other styles are drawn from the logo's own layers
/// (`myTeamsLogoArches`, `myTeamsLogoBars`, `myTeamsLogoMonoWhite`) or by
/// SwiftUI, on the logo's canvas (`canvasAspect`), so each site keeps its
/// frame whatever the style.
///
/// What can't follow the choice, as for the accent: the app icon and the
/// system launch screen (`BrandAccent`).
enum BrandIconStyle: String, CaseIterable, Identifiable, Sendable {
    /// The shipped logo: the T's bars and the arches.
    case classic
    /// The arches alone, filled with the accent.
    case archesOnly
    /// The T's bars alone, filled with the accent.
    case barCrest
    /// The "mT" letterform, set in heavy rounded type in the accent.
    case monogram
    /// The arches as a thin outline in the accent.
    case outline
    /// An accent rounded square with the logo knocked out of it.
    case tile

    /// The `UserDefaults` key the choice is stored under.
    static let storageKey = "settings.brandIconStyle"

    /// The logo's canvas, width over height: every layer of the art is
    /// 798 × 561 px at @3x, and every style is drawn on the same canvas.
    static let canvasAspect: CGFloat = 798.0 / 561.0

    var id: String { rawValue }

    /// Whether this is the shipped logo, which leaves the app as it was.
    var isDefault: Bool { self == .classic }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .archesOnly: "Arches"
        case .barCrest: "Bars"
        case .monogram: "Monogram"
        case .outline: "Outline"
        case .tile: "Tile"
        }
    }
}

extension EnvironmentValues {
    /// The reader's style of the mark, set at the root
    /// (`View.brandIconStyle(_:)`).
    @Entry var brandIconStyle: BrandIconStyle = .classic
}

extension View {
    /// Draws every myTeams mark under the view in `style`
    /// (`\.brandIconStyle`). For the app's root view only, beside
    /// `brandAccent(_:)`, whose colour the style is drawn in.
    func brandIconStyle(_ style: BrandIconStyle) -> some View {
        environment(\.brandIconStyle, style)
    }
}

// MARK: - Drawing

/// The myTeams mark in `style`, on the logo's canvas, in `fill`: the
/// accent's colour or gradient, or the ink a team bar asks for.
///
/// `classic` here is the recoloured logo (bars as drawn, arches in `fill`);
/// the shipped blue's original art is `BrandLogoMark`'s to draw. Resizable
/// and aspect-fit, like the `Image` it stands in for: frame it.
struct BrandIconGlyph: View {
    let style: BrandIconStyle
    let fill: AnyShapeStyle

    var body: some View {
        mark
            .aspectRatio(BrandIconStyle.canvasAspect, contentMode: .fit)
            // One picture: the call site's label and identifier name it.
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var mark: some View {
        switch style {
        case .classic:
            Image("myTeamsLogoBars")
                .resizable()
                .scaledToFit()
                .overlay {
                    BrandArches(fill: fill)
                }
        case .archesOnly:
            BrandArches(fill: fill)
        case .barCrest:
            Rectangle()
                .fill(fill)
                .mask {
                    Image("myTeamsLogoBars")
                        .resizable()
                        .scaledToFit()
                }
        case .monogram:
            BrandMonogram(fill: fill)
        case .outline:
            BrandArchesOutline(fill: fill)
        case .tile:
            BrandTile(fill: fill)
        }
    }
}

/// "mT", the letterform of the name, as large as the canvas holds.
private struct BrandMonogram: View {
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { proxy in
            Text(verbatim: "mT")
                // Fixed: a logo, sized by its frame, not by Dynamic Type.
                .font(.system(size: proxy.size.height * 0.8, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
                .foregroundStyle(fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The arches' outline: the mask spread a little each way, less the mask
/// itself, so the stroke follows the art's own edge.
private struct BrandArchesOutline: View {
    let fill: AnyShapeStyle

    /// The stroke, as a share of the canvas's width.
    private static let lineWidth: CGFloat = 0.018

    /// How many copies spread the mask: enough for an even ring.
    private static let spread = 12

    var body: some View {
        Rectangle()
            .fill(fill)
            .mask {
                GeometryReader { proxy in
                    let width = max(1, proxy.size.width * Self.lineWidth)
                    ZStack {
                        ForEach(0..<Self.spread, id: \.self) { index in
                            arches
                                .offset(Self.offset(index, radius: width))
                        }
                        arches
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
            }
    }

    private var arches: some View {
        Image("myTeamsLogoArches")
            .resizable()
            .scaledToFit()
    }

    /// The `index`th of `spread` points around a circle of `radius`.
    private static func offset(_ index: Int, radius: CGFloat) -> CGSize {
        let angle = Double(index) / Double(spread) * 2 * .pi
        return CGSize(width: CGFloat(cos(angle)) * radius, height: CGFloat(sin(angle)) * radius)
    }
}

/// A rounded square of `fill`, the canvas's height, with the logo cut out
/// of it: whatever is behind shows through the mark.
private struct BrandTile: View {
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(fill)
                Image("myTeamsLogoMonoWhite")
                    .resizable()
                    .scaledToFit()
                    .padding(side * 0.14)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
