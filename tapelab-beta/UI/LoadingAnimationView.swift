import SwiftUI
import Lottie

struct LoadingAnimationView: View {
    var body: some View {
        LottieView(animation: .named("loading"))
            .playing(loopMode: .loop)
            .resizable()
            .frame(width: 150, height: 150)
    }
}

#Preview {
    LoadingAnimationView()
        .background(Color.black)
}
