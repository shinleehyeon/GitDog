// GitHub brand mark (octicon "mark-github") rendered from an embedded SVG via
// NSImage — no bundled asset, and NSImage parses the arcs/curves natively.

import SwiftUI
import AppKit

enum GitHubBrand {
    /// Official GitHub mark, 98×96, black fill (so `isTemplate` recolors cleanly).
    private static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="98" height="96" viewBox="0 0 98 96">\
    <path fill-rule="evenodd" clip-rule="evenodd" d="M48.854 0C21.839 0 0 22 0 49.217c0 \
    21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052\
    -.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448\
    -3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 \
    14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 \
    0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 \
    5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427\
    -5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 \
    0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897\
    -.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 \
    22 75.788 0 48.854 0z" fill="#000"/></svg>
    """

    /// An NSImage of the mark. `template` lets AppKit recolor it (e.g. white on a
    /// dark menu bar).
    static func image(size: CGFloat = 96, template: Bool) -> NSImage? {
        guard let data = svg.data(using: .utf8), let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: size, height: size * (96.0 / 98.0))
        img.isTemplate = template
        return img
    }
}

/// SwiftUI view of the GitHub mark, tintable.
struct GitHubMark: View {
    var color: Color = .white
    var body: some View {
        Group {
            if let img = GitHubBrand.image(template: true) {
                Image(nsImage: img).resizable().renderingMode(.template)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .foregroundColor(color)
    }
}

/// Black rounded speech bubble with a downward tail (login screen).
struct LoginBubble: View {
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Text(text).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.black))
        .overlay(alignment: .bottom) {
            BubbleTail().fill(Color.black)
                .frame(width: 16, height: 9).offset(y: 8)
        }
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
