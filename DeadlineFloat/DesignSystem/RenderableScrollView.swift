import SwiftUI

/// A vertical scroll view that still draws its content during an offscreen
/// render.
///
/// `ScrollView` produces an empty image under `ImageRenderer`, which would make
/// every preview in the README a blank panel. In that pass the content is laid
/// out eagerly inside a `GeometryReader` — which accepts the proposed size
/// rather than demanding its own — and clipped, giving the same framing a
/// scrolled view would have at rest.
struct RenderableScrollView<Content: View>: View {
    var showsIndicators: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.isOffscreenRender) private var isOffscreenRender

    var body: some View {
        if isOffscreenRender {
            GeometryReader { proxy in
                content.frame(width: proxy.size.width, alignment: .topLeading)
            }
            .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                content
            }
            .scrollContentBackground(.hidden)
        }
    }
}
