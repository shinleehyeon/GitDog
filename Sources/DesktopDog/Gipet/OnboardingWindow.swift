import AppKit
import SwiftUI

final class OnboardingWindow: NSWindow {
    private static var instance: OnboardingWindow?

    static func showIfNeeded() {
        let key = "com.gipet.app.onboardingShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let window = OnboardingWindow()
        instance = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "깃독에 오신 걸 환영해요!"
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: OnboardingView(window: self))
        center()
    }
}

private struct OnboardingView: View {
    let window: NSWindow

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("깃독에 오신 걸 환영해요! 🐾")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Row(icon: "menubar.rectangle",
                    text: "메뉴바에 깃독 아이콘이 없나요?\n메뉴바가 가득 차 있다면 다른 앱을 지워서 깃독을 고정하세요.")
                Row(icon: "hand.point.up.left",
                    text: "⌘ 누른 채 드래그하면\n아이콘 위치를 원하는 곳으로 옮길 수 있어요.")
                Row(icon: "pawprint",
                    text: "강아지를 클릭하거나 메뉴바 아이콘을 눌러\ngit 커밋 & 푸시를 해봐요.")
            }
            .padding(.horizontal, 8)

            Button(action: { window.close() }) {
                Text("시작하기")
                    .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 480, height: 360)
    }
}

private struct Row: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
