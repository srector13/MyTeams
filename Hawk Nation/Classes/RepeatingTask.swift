//
//  RepeatingTask.swift
//  myTeams
//
//  Created by Stephen Rector on 1/5/21.
//  Copyright © 2021 Stephen Rector. All rights reserved.
//

import SwiftUI

extension View {
    /// Runs `operation` when the view appears, then again every `interval` for
    /// as long as it stays on screen.
    ///
    /// Live scores and clocks need refetching while a game is in progress. This
    /// replaces the `Timer.publish` and paired `onAppear`/`onReceive` the views
    /// used to do it with: SwiftUI cancels the task when the view goes away, so
    /// a closed sheet stops polling instead of leaving a timer running.
    func task(
        repeatingEvery interval: Duration,
        _ operation: @escaping () async -> Void
    ) -> some View {
        task {
            while !Task.isCancelled {
                await operation()
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }
}
