//
//  RepeatingTask.swift
//  myTeams
//
//  Created by Stephen Rector on 1/5/21.
//  Copyright © 2021 Stephen Rector. All rights reserved.
//

import SwiftUI

extension View {
    /// Runs `operation` when the view appears, then again after whatever delay
    /// it returns, for as long as the view stays on screen. Returning `nil`
    /// stops the loop.
    ///
    /// Live scores and clocks need refetching while a game is in progress, but
    /// a finished game never changes and one days away barely does, so the
    /// operation chooses its own next interval from what it just loaded. This
    /// replaces the `Timer.publish` and paired `onAppear`/`onReceive` the views
    /// used to do it with: SwiftUI cancels the task when the view goes away, so
    /// a closed sheet stops polling instead of leaving a timer running.
    func pollingTask(_ operation: @escaping () async -> Duration?) -> some View {
        task {
            while !Task.isCancelled {
                guard let interval = await operation() else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }
}
