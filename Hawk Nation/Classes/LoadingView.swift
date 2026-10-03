//
//  LoadingView.swift
//  myTeams
//
//  Created by Stephen Rector on 1/5/21.
//  Copyright © 2021 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A pulsing skeleton block. Drawn in the system fill rather than a fixed
/// grey (X-3), which is already translucent, so it pulses between half and
/// full strength: about the weight the grey had at 10–30%. Still under
/// Reduce Motion (X-6); see `Theme.Placeholder`.
public struct LoadingView: View {

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.inner)
            .fill(.fill)
            .placeholderPulse()
            .transition(.opacity)
    }
}


/// `LoadingView` in a circle, for crests and headshots.
public struct LoadingViewCircle: View {

    public init() {}

    public var body: some View {
        Circle()
            .fill(.fill)
            .placeholderPulse()
            .transition(.opacity)
    }
}
