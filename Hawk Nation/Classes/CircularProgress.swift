import SwiftUI

public struct CircularProgress: View {
    var percentage: CGFloat
    var fontSize : CGFloat
    var backgroundColor : Color
    var fontColor : Color
    var borderColor1 : Color
    var borderColor2 : LinearGradient
    
    public init(percentage: CGFloat, fontSize: CGFloat, backgroundColor : Color, fontColor: Color, borderColor1: Color, borderColor2: LinearGradient) {
        self.percentage = percentage
        self.fontSize = fontSize
        self.backgroundColor = backgroundColor
        self.fontColor = fontColor
        self.borderColor1 = borderColor1
        self.borderColor2 = borderColor2
    }

    public var body: some View {
        return (Circle()
                    .foregroundStyle(backgroundColor)
                    .modifier(PercentageIndicator(percentage: self.percentage, fontSize: fontSize, fontColor: fontColor, borderColor1: borderColor1, borderColor2: borderColor2)))
        
    }
}


public struct PercentageIndicator: ViewModifier, Animatable {
    var percentage: CGFloat
    let fontSize : CGFloat
    let fontColor : Color
    let borderColor1 : Color
    let borderColor2 : LinearGradient
    
    public var animatableData: CGFloat {
        get { percentage }
        set { percentage = newValue }
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(CircularProgressView(percentage: percentage, fontSize: fontSize, fontColor: fontColor, borderColor1: borderColor1, borderColor2: borderColor2))
    }
    
    public struct CircularProgressView: View {
        let percentage: CGFloat
        let fontSize : CGFloat
        let fontColor : Color
        let borderColor1 : Color
        let borderColor2 : LinearGradient
        
        public var body: some View {
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.5)
                    //.stroke(lineWidth: 8.0)
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .opacity(0.3)
                    .rotationEffect(Angle(degrees: -180))
                    .foregroundStyle(borderColor1)
                    .padding(.all, 8)
                
                borderColor2
                    .mask(Circle()
                            .trim(from: 0.0, to: self.percentage/2)
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            //.stroke(lineWidth: 8.0)
                            //.rotationEffect(Angle(degrees: 270.0))
                            .rotationEffect(Angle(degrees: -180))
                            .padding(.all, 8)
                    )
                    
                Text("\(Int(percentage * 100))%")
                    .foregroundStyle(fontColor)
                    .font(.system(size: fontSize))
                    .fontWeight(.black)
                   .scaleEffect((percentage/2)+1)
            }
        }
    }
}
