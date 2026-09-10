import SwiftUI
import DuoLidCore

struct PreviewDesktop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.49, green: 0.59, blue: 0.78), Color(red: 0.84, green: 0.73, blue: 0.91), Color(red: 0.96, green: 0.82, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color(red: 0.53, green: 0.40, blue: 0.86)).frame(width: 280, height: 165).rotationEffect(.degrees(-34)).offset(x: -97, y: 68).blur(radius: 18)
                Ellipse().fill(Color(red: 0.98, green: 0.66, blue: 0.55).opacity(0.8)).frame(width: 180, height: 170).offset(x: 145, y: -52).blur(radius: 18)
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.semibold)
                    Text("File   Edit   View")
                    Spacer()
                    Image(systemName: "wifi")
                    Text("9:41")
                }.font(.system(size: 5.5)).padding(.horizontal, 7).frame(height: 12).background(.white.opacity(0.18)).frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach([Color(red: 1, green: 0.49, blue: 0.47), Color(red: 1, green: 0.79, blue: 0.35), Color(red: 0.39, green: 0.81, blue: 0.52)], id: \.self) { Circle().fill($0).frame(width: 4, height: 4) }
                        Spacer()
                    }.padding(7)
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 2).fill(DuoTheme.accent.opacity(0.22)).frame(width: 28, height: 5)
                            ForEach(0..<4) { _ in Capsule().fill(.black.opacity(0.08)).frame(width: 22, height: 3) }
                        }.padding(.leading, 9)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Space to think.").font(.system(size: 12, weight: .semibold)).tracking(-0.4).foregroundStyle(Color(white: 0.14))
                            Text("A little less noise.\nA little more room for you.").font(.system(size: 6)).foregroundStyle(Color(white: 0.48)).lineSpacing(3)
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in RoundedRectangle(cornerRadius: 4).fill([Color(red: 0.89, green: 0.86, blue: 0.97), Color(red: 0.92, green: 0.88, blue: 0.83), Color(red: 0.85, green: 0.9, blue: 0.87)][index]).frame(width: 26, height: 26) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(width: geometry.size.width * 0.65, height: geometry.size.height * 0.65)
                    .background(Color(white: 0.99), in: RoundedRectangle(cornerRadius: 5))
                    .shadow(color: .black.opacity(0.13), radius: 8, y: 5)
                    .offset(x: -13, y: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "sun.max.fill").font(.system(size: 12)).foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.42))
                    Text("24°").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                    Text("A lovely day.").font(.system(size: 6)).foregroundStyle(.white.opacity(0.85))
                }.frame(width: 60, height: 69).background(LinearGradient(colors: [Color(red: 0.39, green: 0.56, blue: 0.77), Color(red: 0.59, green: 0.69, blue: 0.84)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 5).offset(x: 98, y: 24)
                HStack(spacing: 4) {
                    ForEach(0..<7) { index in
                        RoundedRectangle(cornerRadius: 3).fill([Color.blue, Color.white, Color.orange, Color.purple, Color.green, Color.gray, Color.blue][index].opacity(0.88)).frame(width: 12, height: 12)
                    }
                }.padding(4).background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 6)).padding(.bottom, 4).frame(maxHeight: .infinity, alignment: .bottom)
            }.clipped()
        }
    }
}
