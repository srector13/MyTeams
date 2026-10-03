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
/// full strength: about the weight the grey had at 10–30%.
public struct LoadingView: View {

    private struct Constants {
        static let duration: Double = 2.0
        static let minOpacity: Double = 0.5
        static let maxOpacity: Double = 1
        static let cornerRadius: CGFloat = Theme.Radius.inner
    }

    @State private var opacity: Double = Constants.minOpacity

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(.fill)
            .opacity(opacity)
            .transition(.opacity)
            .onAppear {
                let baseAnimation = Animation.easeInOut(duration: Constants.duration)
                let repeated = baseAnimation.repeatForever(autoreverses: true)
                withAnimation(repeated) {
                    self.opacity = Constants.maxOpacity
                }
        }
    }
}


/// `LoadingView` in a circle, for crests and headshots.
public struct LoadingViewCircle: View {

    private struct Constants {
        static let duration: Double = 2.0
        static let minOpacity: Double = 0.5
        static let maxOpacity: Double = 1
    }

    @State private var opacity: Double = Constants.minOpacity

    public init() {}

    public var body: some View {
        Circle()
            .fill(.fill)
            .opacity(opacity)
            .transition(.opacity)
            .onAppear {
                let baseAnimation = Animation.easeInOut(duration: Constants.duration)
                let repeated = baseAnimation.repeatForever(autoreverses: true)
                withAnimation(repeated) {
                    self.opacity = Constants.maxOpacity
                }
        }
    }
}
