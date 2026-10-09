//
//  CalendarWriter.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import EventKit
import EventKitUI
import SwiftUI

/// Writes `EventDraft`s to the reader's calendar (R-7). EventKit glue only:
/// what goes in each event is `CalendarEventBuilder`'s business.
///
/// A season sync needs full access, not write-only: it reads back the
/// events it wrote before, by their marker, and makes a calendar of its
/// own, neither of which write-only access allows. One game goes through
/// `EventEditSheet`, which needs no access at all.
enum CalendarWriter {
    /// What a season sync did.
    struct Summary: Equatable, Sendable {
        var added = 0
        var updated = 0
        var unchanged = 0
        var calendarTitle = ""

        /// "Added 12 games and updated 2 in "myTeams – Kansas City Chiefs"."
        var message: String {
            var parts: [String] = []
            if added > 0 { parts.append("added \(games(added))") }
            if updated > 0 { parts.append("updated \(games(updated))") }
            guard !parts.isEmpty else {
                return "Your calendar \u{201C}\(calendarTitle)\u{201D} is already up to date."
            }
            let done = parts.joined(separator: " and ")
            return "\(done.prefix(1).uppercased())\(done.dropFirst()) in \u{201C}\(calendarTitle)\u{201D}."
        }

        private func games(_ count: Int) -> String {
            count == 1 ? "1 game" : "\(count) games"
        }
    }

    enum Failure: LocalizedError {
        case denied
        case noSource

        var errorDescription: String? {
            switch self {
            case .denied:
                return "myTeams can\u{2019}t reach your calendars. You can allow it in Settings \u{203A} Privacy & Security \u{203A} Calendars."
            case .noSource:
                return "There\u{2019}s no calendar account on this device to add a calendar to."
            }
        }
    }

    /// How far back a sync looks for events it wrote, so a game brought
    /// forward, or one already past, is still found and not added again.
    private static let lookBehind: TimeInterval = 60 * 86_400

    /// Adds `drafts` to the calendar titled `calendarTitle`, making it if
    /// there is none, and moves or updates any game already there (found by
    /// the marker in its notes) instead of adding it twice.
    ///
    /// Nonisolated, with a store of its own: `EKEventStore` isn't
    /// `Sendable`, and a store made here never leaves this call.
    static func syncSeason(_ drafts: [EventDraft], calendarTitle: String) async throws -> Summary {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw Failure.denied }

        let calendar = try findOrCreateCalendar(titled: calendarTitle, in: store)
        var summary = Summary(calendarTitle: calendarTitle)
        guard let first = drafts.map(\.start).min(), let last = drafts.map(\.end).max() else {
            return summary
        }

        // EventKit searches a span of at most four years; a season is
        // well inside it.
        let predicate = store.predicateForEvents(
            withStart: min(first, Date()).addingTimeInterval(-lookBehind),
            end: last.addingTimeInterval(lookBehind),
            calendars: [calendar]
        )
        var existing: [String: EKEvent] = [:]
        for event in store.events(matching: predicate) {
            if let id = CalendarEventBuilder.eventID(inNotes: event.notes) {
                existing[id] = event
            }
        }

        for draft in drafts {
            let event = existing[draft.eventID]
            switch CalendarEventBuilder.action(for: draft, existing: event.map(snapshot)) {
            case .add:
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                apply(draft, to: event)
                try store.save(event, span: .thisEvent, commit: false)
                summary.added += 1
            case .update:
                guard let event else { continue }
                apply(draft, to: event)
                try store.save(event, span: .thisEvent, commit: false)
                summary.updated += 1
            case .unchanged:
                summary.unchanged += 1
            }
        }
        try store.commit()
        return summary
    }

    /// Copies a draft onto an event.
    static func apply(_ draft: EventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.location = draft.location
        event.notes = draft.notes
        event.isAllDay = false
    }

    /// An event's fields as a draft would hold them; EventKit may give an
    /// empty location or notes back as `nil` or as empty text.
    private static func snapshot(_ event: EKEvent) -> CalendarEventBuilder.Snapshot {
        let location = event.location ?? ""
        return CalendarEventBuilder.Snapshot(
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            location: location.isEmpty ? nil : location,
            notes: event.notes ?? ""
        )
    }

    /// The writable calendar titled `title`, or a new one by that name in
    /// the account new events go to by default (else the device's own, else
    /// the first iCloud or CalDAV account).
    private static func findOrCreateCalendar(titled title: String, in store: EKEventStore) throws -> EKCalendar {
        if let calendar = store.calendars(for: .event).first(where: { $0.title == title && $0.allowsContentModifications }) {
            return calendar
        }
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first { $0.sourceType == .calDAV }
        guard let source else { throw Failure.noSource }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

/// The system's new-event sheet, filled in from a draft, for adding one
/// game (R-7). It runs out of process, so the reader picks the calendar and
/// saves without the app being granted any access to their calendars.
struct EventEditSheet: UIViewControllerRepresentable {
    let draft: EventDraft
    /// Called when the reader saves or cancels.
    var onDone: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        CalendarWriter.apply(draft, to: event)
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        context.coordinator.onDone = onDone
    }

    /// Forwards Save and Cancel to SwiftUI, whose sheet `dismiss` closes
    /// the editor and clears the binding that presented it, as `SafariView`
    /// does.
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var onDone: (() -> Void)?

        init(onDone: (() -> Void)?) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone?()
        }
    }
}
