import SwiftUI
import Lottie

struct LottieView: NSViewRepresentable {
    var animationName: String = "dog_animation"

    func makeNSView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.loopMode = .loop
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .continuePlaying
        view.translatesAutoresizingMaskIntoConstraints = false
        view.animation = loadAnimation(name: animationName)
        view.play()
        return view
    }

    func updateNSView(_ nsView: LottieAnimationView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LottieAnimationView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 200)
    }
}

// Dog with a looping click-hint overlay. Tapping hides the overlay and calls action.
struct LottieLoginButton: View {
    let action: () -> Void
    @State private var showClickHint = true

    var body: some View {
        ZStack(alignment: .center) {
            LottieView(animationName: "dog_animation")
                .frame(width: 200, height: 200)
            LottieView(animationName: "dog_click")
                .frame(width: 90, height: 90)
                .offset(x: 60, y: 30)
                .opacity(showClickHint ? 1 : 0)
        }
        .frame(width: 200, height: 200)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            showClickHint = false
            action()
        }
    }
}

func loadAnimation(name: String) -> LottieAnimation? {
    let candidates: [Bundle] = [Bundle.module, Bundle.main]
    for b in candidates {
        if let url = b.url(forResource: name, withExtension: "json") {
            return LottieAnimation.filepath(url.path)
        }
    }
    if let spm = Bundle(path: Bundle.main.bundlePath + "/Contents/Resources/DesktopGoose_DesktopGoose.bundle"),
       let url = spm.url(forResource: name, withExtension: "json") {
        return LottieAnimation.filepath(url.path)
    }
    return nil
}
