import KyoCore
import SwiftUI

/// The notch outline: flared "ears" where it meets the screen edge, round at the bottom.
struct NotchShape: Shape {
    var ear: CGFloat
    var corner: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, corner) }
        set {
            ear = newValue.first
            corner = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let corner = max(0, min(corner, rect.height / 2, (rect.width - 2 * ear) / 2))
        let ear = min(ear, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear + corner, y: rect.maxY),
            control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.maxY - corner),
            control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel

    /// Room left around the open panel for its shadow.
    static let margin: CGFloat = 28

    /// Width of the flared ear either side, which the window has to allow for.
    static func ear(for state: NotchState) -> CGFloat { state == .open ? 10 : 6 }

    var body: some View {
        let metrics = model.metrics
        let state = model.state
        let open = state == .open
        let ear = Self.ear(for: state)
        let shape = NotchShape(ear: ear, corner: open ? 22 : 9)
        let size = metrics.size(for: state, contentHeight: model.contentHeight)
        let late = open && model.content?.tone == .late

        ZStack(alignment: .top) {
            if let content = model.content {
                Group {
                    if let agenda = content.agenda {
                        agendaList(agenda, heading: content)
                    } else {
                        row(content)
                    }
                }
                .frame(
                    width: metrics.size(for: .open).width, height: content.height, alignment: .top
                )
                .padding(.top, metrics.notchHeight)
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)

                pill(content, metrics: metrics)
                    .opacity(state == .compact ? 1 : 0)
                    .allowsHitTesting(state == .compact)
            }
        }
        .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
        // The row keeps its full size while the panel grows, so clip it to the outline.
        .clipShape(shape)
        .background {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 10, y: 5)
        }
        .background {
            if late { LateGlow(shape: shape) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.contentHeight)
        .animation(.easeInOut(duration: 0.25), value: model.content?.tone)
    }

    // MARK: Full panel

    private func row(_ content: NotchContent) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color(for: content.tone))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(content.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 8)

            if let emphasis = content.emphasis {
                Text(emphasis)
                    .font(
                        content.tone == .urgent
                            ? .system(size: 24, weight: .semibold, design: .rounded)
                            : .system(size: 13, weight: .medium)
                    )
                    .monospacedDigit()
                    .foregroundStyle(color(for: content.tone))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: emphasis)
                    .fixedSize()
            }

            if let label = content.actionLabel {
                Button(label, action: model.onAction)
                    .buttonStyle(PillButtonStyle(fill: buttonFill(for: content.tone)))
            }

            if content.canSnooze {
                roundButton("moon.zzz.fill", help: "Snooze", action: model.onSnooze)
            }
            roundButton("xmark", help: "Dismiss", action: model.onDismiss)
        }
        .padding(.horizontal, 20)
        .frame(height: NotchMetrics.rowHeight)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Today

    private func agendaList(_ rows: [AgendaRow], heading: NotchContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(heading.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(heading.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                roundButton("xmark", help: "Dismiss", action: model.onDismiss)
            }
            .lineLimit(1)
            .frame(height: AgendaRow.headerHeight)

            if rows.isEmpty {
                Text("Nothing on today")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: AgendaRow.height)
            }
            ForEach(rows) { row in
                if row.hasCall {
                    Button {
                        model.onOpenRow(row.id)
                    } label: {
                        agendaRow(row)
                    }
                    .buttonStyle(.plain)
                    .help(row.linkHost.map { "Open \($0)" } ?? "Open the call")
                } else {
                    agendaRow(row)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func agendaRow(_ row: AgendaRow) -> some View {
        HStack(spacing: 8) {
            Text(row.time)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 96, alignment: .leading)
            Text(row.title)
                .font(.system(size: 13, weight: row.status == .next ? .semibold : .regular))
                .foregroundStyle(.white)
            if row.hasCall {
                // A camera for a call; a plain link, with its site named on
                // hover, for anything else.
                Image(systemName: row.linkHost == nil ? "video.fill" : "link")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            if let trailing = row.trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(row.status == .now ? .green : .white.opacity(0.7))
                    .fixedSize()
            }
        }
        .lineLimit(1)
        .frame(height: AgendaRow.height)
        .opacity(row.status == .past ? 0.4 : 1)
        // The whole width takes the click, not only the text.
        .contentShape(Rectangle())
    }

    // MARK: Pill

    /// A dot left of the notch and the minutes to go right of it. Click to expand.
    private func pill(_ content: NotchContent, metrics: NotchMetrics) -> some View {
        let size = metrics.size(for: .compact)
        return HStack(spacing: 0) {
            Circle()
                .fill(color(for: content.tone))
                .frame(width: 7, height: 7)
                .frame(width: NotchMetrics.wing)

            Group {
                if metrics.hasNotch {
                    // The camera housing covers this part.
                    Color.clear
                } else {
                    Text(content.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .frame(width: metrics.notchWidth)

            Text(content.compactText ?? "")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                .frame(width: NotchMetrics.wing)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: model.onTap)
    }

    // MARK: Colours

    private static let lateColor = Color(red: 1, green: 0.27, blue: 0.23)

    private func color(for tone: NotchContent.Tone) -> Color {
        switch tone {
        case .calm: .white.opacity(0.7)
        case .soon: .white
        case .urgent: .orange
        case .live: .green
        case .late: Self.lateColor
        }
    }

    /// Open is filled once the meeting has started.
    private func buttonFill(for tone: NotchContent.Tone) -> Color? {
        switch tone {
        case .live: .green
        case .late: Self.lateColor
        case .calm, .soon, .urgent: nil
        }
    }

    /// A red glow that breathes behind the panel when a meeting is being missed.
    private struct LateGlow: View {
        let shape: NotchShape
        @State private var bright = false

        var body: some View {
            shape
                .fill(.black)
                .shadow(color: NotchView.lateColor.opacity(bright ? 0.95 : 0.15), radius: 14)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        bright = true
                    }
                }
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    /// Nil for the quiet, translucent look.
    var fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(fill == nil ? .white : .black)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(fill ?? Color.white.opacity(0.18), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
