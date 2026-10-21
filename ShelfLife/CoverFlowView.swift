import SwiftUI

/// iPod-style Cover Flow: swipe through covers, tap the centre one to open it.
struct CoverFlowView: View {
    let items: [MediaItem]
    let onOpen: (MediaItem) -> Void

    @State private var selectedID: UUID?

    /// Degrees each side cover is turned. Flip the sign to angle them the other way.
    private let tilt: Double = -55

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedID } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let coverWidth = min(geo.size.width * 0.6, 300, geo.size.height * 0.38)
            let cardHeight = coverWidth * 1.4

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -coverWidth * 0.42) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            CoverFlowCard(item: item, width: coverWidth, height: cardHeight)
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .rotation3DEffect(.degrees(phase.value * tilt),
                                                          axis: (x: 0, y: 1, z: 0),
                                                          perspective: 0.5)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.84)
                                        .brightness(phase.isIdentity ? 0 : -0.3)
                                }
                                // Covers nearer the middle sit on top of the stack.
                                .zIndex(-Double(abs(index - selectedIndex)))
                                .onTapGesture {
                                    if item.id == selectedID {
                                        onOpen(item)
                                    } else {
                                        withAnimation(.spring(duration: 0.4)) { selectedID = item.id }
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(item.displayTitle), \(item.subtitle)")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - coverWidth) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID, anchor: .center)
                .frame(height: cardHeight * 1.38)

                caption
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                Spacer(minLength: 12)

                if items.count > 1 {
                    scrubber
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(
            LinearGradient(colors: [Color(white: 0.16), .black, .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: selectedID)
        .onAppear(perform: ensureSelection)
        .onChange(of: items.map(\.id)) { _, _ in ensureSelection() }
    }

    private var caption: some View {
        let item = items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
        return VStack(spacing: 4) {
            Text(item?.displayTitle ?? "")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(item?.subtitle ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let value = item?.formattedValue {
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: selectedID)
    }

    /// Drag along this to whizz through a big collection, like the iPod's scroll wheel.
    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { Double(selectedIndex) },
                set: { newValue in
                    let i = Int(newValue.rounded())
                    if items.indices.contains(i) { selectedID = items[i].id }
                }
            ), in: 0...Double(max(items.count - 1, 1)), step: 1)
            .tint(.white.opacity(0.7))
            Text("\(selectedIndex + 1) of \(items.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func ensureSelection() {
        if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
    }
}

struct CoverFlowCard: View {
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat

    private var coverHeight: CGFloat { width * item.format.coverAspect }

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            cover
            // Mirror-image reflection on the "floor".
            cover
                .scaleEffect(x: 1, y: -1)
                .frame(height: coverHeight * 0.35, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(colors: [.white.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height * 1.35, alignment: .bottom)
    }

    private var cover: some View {
        Group {
            if let data = item.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: coverHeight)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if item.isWishlist {
                Image(systemName: "star.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow, .black.opacity(0.6))
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
    }

    /// Something nicer than a blank square when there's no cover yet.
    private var placeholder: some View {
        // Stable colour per title (Swift's hashValue changes every launch).
        let seed = item.displayTitle.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        let hue = Double(seed) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.55),
                                    Color(hue: hue, saturation: 0.7, brightness: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: item.format.symbol)
                    .font(.system(size: width * 0.22))
                    .foregroundStyle(.white.opacity(0.85))
                Text(item.displayTitle)
                    .font(.system(size: max(12, width * 0.075), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
                Text(item.format.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
