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
                    .foregroundColor(backgroundColor)
                    .modifier(PercentageIndicator(percentage: self.percentage, fontSize: fontSize, fontColor: fontColor, borderColor1: borderColor1, borderColor2: borderColor2)))
        
    }
}


public struct PercentageIndicator: AnimatableModifier {
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
                    .foregroundColor(borderColor1)
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
                    .foregroundColor(fontColor)
                    .font(.system(size: fontSize))
                    .fontWeight(.black)
                   .scaleEffect((percentage/2)+1)
            }
        }
    }
}


public struct LinearProgress: View {
    var percentage: CGFloat
    var backgroundColor : Color
    var borderColor1 : Color
    var borderColor2 : LinearGradient
    
    public init(percentage: CGFloat, backgroundColor : Color, borderColor1: Color, borderColor2: LinearGradient) {
        self.percentage = percentage
        self.backgroundColor = backgroundColor
        self.borderColor1 = borderColor1
        self.borderColor2 = borderColor2
    }

    public var body: some View {
        return (RoundedRectangle(cornerRadius: 20)
                    .foregroundColor(backgroundColor)
                    .modifier(LinearPercentageIndicator(percentage: self.percentage, borderColor1: borderColor1, borderColor2: borderColor2)))
        
    }
}


public struct LinearPercentageIndicator: AnimatableModifier {
    var percentage: CGFloat
    let borderColor1 : Color
    let borderColor2 : LinearGradient
    
    public var animatableData: CGFloat {
        get { percentage }
        set { percentage = newValue }
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(LinearProgressView(percentage: percentage, borderColor1: borderColor1, borderColor2: borderColor2))
    }
    
    public struct LinearProgressView: View {
        let percentage: CGFloat
        let borderColor1 : Color
        let borderColor2 : LinearGradient
        
        public var body: some View {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .opacity(0.3)
                    .foregroundColor(borderColor1)
                    .padding(.all, 8)
                
                borderColor2
                    .mask(RoundedRectangle(cornerRadius: 20)
                            //.trim(from: 0.0, to: self.percentage)
                            .frame(height: 70)
                            .padding(.all, 8)
                    )
            }
        }
    }
}


struct Progress_Previews: PreviewProvider {
    static var previews: some View {
        LinearProgress(percentage: 0.5,
                          backgroundColor: Color(UIColor.systemBackground),
                          borderColor1: Color(UIColor.blue),
                          borderColor2: LinearGradient(gradient: /*@START_MENU_TOKEN@*/Gradient(colors: [Color.red, Color.blue])/*@END_MENU_TOKEN@*/, startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/)).frame(height: 70, alignment: .center)
    }
}



