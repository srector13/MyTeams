//
//  LoadingView.swift
//  myTeams
//
//  Created by Stephen Rector on 1/5/21.
//  Copyright © 2021 Stephen Rector. All rights reserved.
//

import SwiftUI

@available(iOS 13.0, *)
public struct LoadingView: View {
    
    private struct Constants {
        static let duration: Double = 2.0
        static let minOpacity: Double = 0.1
        static let maxOpacity: Double = 0.3
        static let cornerRadius: CGFloat = 10.0
    }
    
    @State private var opacity: Double = Constants.minOpacity
    
    public init() {}
    
    public var body: some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color(UIColor.systemGray))
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


public struct LoadingViewCircle: View {
    
    private struct Constants {
        static let duration: Double = 2.0
        static let minOpacity: Double = 0.1
        static let maxOpacity: Double = 0.3
    }
    
    @State private var opacity: Double = Constants.minOpacity
    
    public init() {}
    
    public var body: some View {
        Circle()
            .fill(Color(UIColor.systemGray))
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
