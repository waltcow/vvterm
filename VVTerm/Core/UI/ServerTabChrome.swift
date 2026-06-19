import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ServerViewTabNavigationButton: View {
    let icon: String
    let action: () -> Void
    var help: String = ""

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                #if os(macOS)
                .background(
                    isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                    in: Circle()
                )
                #else
                .background(
                    isHovering ? Color.gray.opacity(0.3) : Color.clear,
                    in: Circle()
                )
                #endif
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .help(help)
    }
}

struct ServerViewNewTabButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                #if os(macOS)
                .background(
                    isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                    in: Circle()
                )
                #else
                .background(
                    isHovering ? Color.gray.opacity(0.3) : Color.clear,
                    in: Circle()
                )
                #endif
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .help(Text(help))
    }
}

enum ServerViewTopTabBarMetrics {
    static let tabHeight: CGFloat = 36
    static let tabVerticalPadding: CGFloat = 7
    static let barVerticalInset: CGFloat = 4
    static let tabSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 4
    static let outerHorizontalPadding: CGFloat = 12
    #if os(macOS)
    static let toolbarTabCapsuleHeight: CGFloat = 26
    static let toolbarTabStripMinWidth: CGFloat = 180
    static let toolbarTabStripIdealWidth: CGFloat = 640
    static let toolbarTabStripFallbackWidth: CGFloat = 1_600
    #endif
    static var barHeight: CGFloat { tabHeight + barVerticalInset * 2 }
}

#if os(macOS)
struct ServerToolbarTabCell: View {
    let title: String
    let isSelected: Bool
    let statusColor: Color
    let width: CGFloat
    var accessibilityLabel: String?
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                tabSurface
                tabLabel
            }
            .frame(width: width, height: ServerViewTopTabBarMetrics.toolbarTabCapsuleHeight)
            .frame(width: width, height: ServerViewTopTabBarMetrics.tabHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
    }

    @ViewBuilder
    private var tabLabel: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                    )
            }
            .buttonStyle(.plain)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(
            width: width,
            height: ServerViewTopTabBarMetrics.toolbarTabCapsuleHeight,
            alignment: .leading
        )
    }

    @ViewBuilder
    private var tabSurface: some View {
        if isSelected {
            selectedGlassSurface
        } else if isHovering {
            Capsule()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
        }
    }

    @ViewBuilder
    private var selectedGlassSurface: some View {
        if reduceTransparency {
            Capsule()
                .fill(.regularMaterial)
        } else if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                Capsule()
                    .fill(.clear)
                    .frame(width: width, height: ServerViewTopTabBarMetrics.toolbarTabCapsuleHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }
}

struct AdaptiveServerTabSizing: Equatable {
    let tabWidth: CGFloat
    let isScrollable: Bool

    static func resolve(
        containerWidth: CGFloat,
        itemCount: Int,
        minimumTabWidth: CGFloat = 72,
        horizontalPadding: CGFloat = ServerViewTopTabBarMetrics.horizontalPadding,
        tabSpacing: CGFloat = ServerViewTopTabBarMetrics.tabSpacing
    ) -> AdaptiveServerTabSizing {
        let resolvedContainerWidth = containerWidth.isFinite
            ? containerWidth
            : ServerViewTopTabBarMetrics.toolbarTabStripFallbackWidth

        guard itemCount > 0, resolvedContainerWidth > 0 else {
            return AdaptiveServerTabSizing(tabWidth: minimumTabWidth, isScrollable: false)
        }

        let availableWidth = max(resolvedContainerWidth - horizontalPadding * 2, 0)
        let totalSpacing = tabSpacing * CGFloat(max(itemCount - 1, 0))
        let candidateWidth = (availableWidth - totalSpacing) / CGFloat(itemCount)

        guard candidateWidth.isFinite, candidateWidth >= minimumTabWidth else {
            return AdaptiveServerTabSizing(tabWidth: minimumTabWidth, isScrollable: true)
        }

        return AdaptiveServerTabSizing(
            tabWidth: candidateWidth,
            isScrollable: false
        )
    }
}

struct AdaptiveServerTabStrip<Item: Identifiable, TabContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let selectedId: Item.ID?
    var minimumTabWidth: CGFloat = 72
    var tabContent: (Item, CGFloat) -> TabContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let sizing = AdaptiveServerTabSizing.resolve(
                containerWidth: proxy.size.width,
                itemCount: items.count,
                minimumTabWidth: minimumTabWidth
            )

            ScrollViewReader { scrollProxy in
                Group {
                    if sizing.isScrollable {
                        ScrollView(.horizontal, showsIndicators: false) {
                            tabStack(tabWidth: sizing.tabWidth)
                        }
                    } else {
                        tabStack(tabWidth: sizing.tabWidth)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .transaction { transaction in
                    if reduceMotion {
                        transaction.animation = nil
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.14),
                    value: sizing
                )
                .onChange(of: selectedId) { newValue in
                    guard sizing.isScrollable, let newValue else { return }
                    withOptionalTabAnimation {
                        scrollProxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: items.map(\.id)) { _ in
                    guard sizing.isScrollable, let selectedId else { return }
                    withOptionalTabAnimation {
                        scrollProxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
        .frame(
            minWidth: minimumTabWidth,
            idealWidth: ServerViewTopTabBarMetrics.toolbarTabStripIdealWidth,
            maxWidth: .infinity,
            minHeight: ServerViewTopTabBarMetrics.tabHeight,
            maxHeight: ServerViewTopTabBarMetrics.tabHeight
        )
    }

    private func tabStack(tabWidth: CGFloat) -> some View {
        HStack(spacing: ServerViewTopTabBarMetrics.tabSpacing) {
            ForEach(items) { item in
                tabContent(item, tabWidth)
                    .id(item.id)
            }
        }
        .padding(.horizontal, ServerViewTopTabBarMetrics.horizontalPadding)
        .frame(height: ServerViewTopTabBarMetrics.tabHeight)
    }

    private func withOptionalTabAnimation(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.14), action)
        }
    }
}

struct ServerToolbarTabStrip<Item: Identifiable, TabContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let selectedId: Item.ID?
    let previousHelp: String
    let nextHelp: String
    let newHelp: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onNew: () -> Void
    var tabContent: (Item, CGFloat) -> TabContent

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                ServerViewTabNavigationButton(
                    icon: "chevron.left",
                    action: onPrevious,
                    help: previousHelp
                )
                .disabled(items.count <= 1)

                ServerViewTabNavigationButton(
                    icon: "chevron.right",
                    action: onNext,
                    help: nextHelp
                )
                .disabled(items.count <= 1)
            }
            .padding(.leading, 8)

            AdaptiveServerTabStrip(items: items, selectedId: selectedId, tabContent: tabContent)
                .layoutPriority(1)

            ServerViewNewTabButton(
                help: newHelp,
                action: onNew
            )
            .padding(.trailing, 8)
        }
        .frame(
            minWidth: ServerViewTopTabBarMetrics.toolbarTabStripMinWidth,
            idealWidth: ServerViewTopTabBarMetrics.toolbarTabStripIdealWidth,
            maxWidth: .infinity
        )
    }
}

#endif
