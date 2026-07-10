import SwiftUI

struct NoticeBannerView: View {
    let item: NoticeItem
    var surfaceStyle: NoticeSurfaceStyle = .standard

    var body: some View {
        NoticeGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                leadingView

                VStack(alignment: .leading, spacing: item.title == nil ? 0 : 2) {
                    if let title = item.title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(surfaceStyle.primaryForegroundColor)
                            .lineLimit(1)
                    }

                    Text(item.message)
                        .font(.subheadline)
                        .foregroundStyle(surfaceStyle.secondaryForegroundColor)
                        .lineLimit(item.title == nil ? 2 : 1)
                }

                Spacer(minLength: 8)

                if let action = item.action {
                    Button(action.title, role: action.role, action: action.handler)
                        .noticeSecondaryButtonStyle()
                        .font(.caption.weight(.semibold))
                }

                if let dismissAction = item.dismissAction {
                    Button(action: dismissAction) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(surfaceStyle.secondaryForegroundColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: NoticeMetrics.bannerMaxWidth, alignment: .leading)
            .noticeSurface(
                style: surfaceStyle,
                prominence: .emphasized,
                cornerRadius: NoticeMetrics.notificationCornerRadius,
                shadowRadius: 14,
                shadowY: 8
            )
            .accessibilityIdentifier("vvterm.notice.banner")
        }
    }

    @ViewBuilder
    private var leadingView: some View {
        switch resolvedLeading {
        case .none:
            EmptyView()
        case .activity:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(item.level.tintColor)
                .controlSize(.small)
        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.level.tintColor)
        }
    }

    private var resolvedLeading: NoticeLeading {
        switch item.leading {
        case .none:
            return .icon(item.level.defaultIconSystemName)
        default:
            return item.leading
        }
    }

}
