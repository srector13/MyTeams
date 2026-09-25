//
//  MyTeamsApp.swift
//  myTeams
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

@main
struct MyTeamsApp: App {
    var body: some Scene {
        WindowGroup {
            Home()
        }
    }
}

extension EnvironmentValues {
    /// The size of the window the app is drawn into.
    ///
    /// The layouts size a good deal of their content against the full width of
    /// the screen — news cards, the parallax team crest, the trailing spacer
    /// in each carousel. They used to read `UIScreen.main.bounds` for it, which
    /// is deprecated, is not reactive, and reports the whole display rather
    /// than the app's share of it when the window is not full screen. `Home`
    /// measures its own container instead and publishes the result here.
    @Entry var containerSize: CGSize = .zero
}
