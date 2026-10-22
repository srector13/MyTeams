//
//  HomeCustomization.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// One of Home's sections under the hero, which the reader can hide and
/// reorder (`HomeCustomizeSheet`). The hero always shows.
enum HomeSectionKind: String, CaseIterable, Identifiable, Sendable {
    case myTeams
    case week
    case standings
    case performers
    case news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myTeams: "My Teams"
        case .week: "This Week"
        case .standings: "Standings"
        case .performers: "Top Performers"
        case .news: "News"
        }
    }

    /// The SF Symbol in the section's header and its row in the sheet.
    var systemImage: String {
        switch self {
        case .myTeams: "star"
        case .week: "calendar"
        case .standings: "list.number"
        case .performers: "trophy"
        case .news: "newspaper"
        }
    }

    /// Where the section sits on an iPad (B-14, H10).
    enum RegularColumn: Sendable {
        /// The left column: the teams and their week.
        case leading
        /// The right column: the tables, beside them.
        case trailing
        /// Full width beneath both columns: the news, whose stories read
        /// better wide than squeezed into half the page.
        case fullWidth
    }

    /// Which column the section takes on an iPad, so the two columns come
    /// out about the same height (H10): My Teams and This Week on the left,
    /// Standings and Top Performers on the right, the news under both.
    var regularColumn: RegularColumn {
        switch self {
        case .myTeams, .week: .leading
        case .standings, .performers: .trailing
        case .news: .fullWidth
        }
    }
}

/// Home's sections in the reader's order, and which are hidden, as kept in
/// `@AppStorage(storageKey)`: the raw values comma-separated, a hidden one
/// prefixed `-` — `"week,myTeams,-standings,performers,news"`.
///
/// Read leniently, so an update's new section shows up: a value it doesn't
/// know is dropped, and a section the string doesn't name is added after
/// the others, shown. An empty string is the default layout.
struct HomeSectionLayout: Equatable, Sendable {
    /// The `UserDefaults` key.
    static let storageKey = "home.sections"

    private static let hiddenPrefix = "-"

    /// Every section, in order, shown or hidden.
    var order: [HomeSectionKind]
    var hidden: Set<HomeSectionKind>

    /// Every section, in `HomeSectionKind`'s order, none hidden.
    static let standard = HomeSectionLayout(order: HomeSectionKind.allCases, hidden: [])

    init(order: [HomeSectionKind], hidden: Set<HomeSectionKind>) {
        self.order = order
        self.hidden = hidden
    }

    /// Reads a stored layout. See the type's documentation.
    init(storage: String) {
        var order: [HomeSectionKind] = []
        var hidden: Set<HomeSectionKind> = []
        for token in storage.split(separator: ",") {
            var value = token.trimmingCharacters(in: .whitespaces)
            let isHidden = value.hasPrefix(Self.hiddenPrefix)
            if isHidden {
                value.removeFirst(Self.hiddenPrefix.count)
            }
            guard let kind = HomeSectionKind(rawValue: value), !order.contains(kind) else { continue }
            order.append(kind)
            if isHidden {
                hidden.insert(kind)
            }
        }
        for kind in HomeSectionKind.allCases where !order.contains(kind) {
            order.append(kind)
        }
        self.init(order: order, hidden: hidden)
    }

    /// The layout as stored.
    var storage: String {
        order
            .map { hidden.contains($0) ? Self.hiddenPrefix + $0.rawValue : $0.rawValue }
            .joined(separator: ",")
    }

    /// The sections Home draws, in order.
    var visible: [HomeSectionKind] {
        order.filter { !hidden.contains($0) }
    }

    /// `kind` shown or hidden.
    func setting(_ kind: HomeSectionKind, shown: Bool) -> HomeSectionLayout {
        var next = self
        if shown {
            next.hidden.remove(kind)
        } else {
            next.hidden.insert(kind)
        }
        return next
    }

    /// The sections at `source` moved to `destination`, as a list's
    /// `onMove` reports it.
    func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> HomeSectionLayout {
        var next = self
        next.order.move(fromOffsets: source, toOffset: destination)
        return next
    }
}

/// "Customize Home": every section under the hero with a switch to show
/// or hide it, in Home's order, dragged to reorder. Saved as it changes,
/// so Home underneath follows along.
struct HomeCustomizeSheet: View {
    @AppStorage(HomeSectionLayout.storageKey) private var storage = ""

    @Environment(\.dismiss) private var dismiss

    private var layout: HomeSectionLayout { HomeSectionLayout(storage: storage) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order) { kind in
                        Toggle(isOn: shown(kind)) {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                        .accessibilityIdentifier("home.customize.\(kind.rawValue)")
                    }
                    .onMove { source, destination in
                        storage = layout.moving(fromOffsets: source, toOffset: destination).storage
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Your next game always leads Home. Tap Edit to drag the sections into the order you like.")
                }

                Section {
                    Button("Restore Default Layout") {
                        storage = HomeSectionLayout.standard.storage
                    }
                    .disabled(layout == .standard)
                    .accessibilityIdentifier("home.customize.reset")
                }
            }
            .navigationTitle("Customize Home")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("home.customize.done")
                }
            }
        }
        // Full height, so every section and Restore Default Layout are in
        // view without dragging the sheet up (H6).
        .presentationDetents([.large])
    }

    /// Whether `kind` shows, saved as it's switched.
    private func shown(_ kind: HomeSectionKind) -> Binding<Bool> {
        Binding {
            !layout.hidden.contains(kind)
        } set: { isShown in
            storage = layout.setting(kind, shown: isShown).storage
        }
    }
}

#Preview {
    HomeCustomizeSheet()
}
