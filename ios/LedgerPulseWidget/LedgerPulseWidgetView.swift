import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct LedgerPulseEntry: TimelineEntry {
    let date: Date
    let companyName: String
    let companyId: String
    let currencySymbol: String
    let cashInAmount: String
    let cashOutAmount: String
    let lastSyncTimestamp: String
    let isPreview: Bool
}

// MARK: - Timeline Provider
struct LedgerPulseTimelineProvider: TimelineProvider {
    typealias Entry = LedgerPulseEntry
    private let appGroupId = "group.com.ledgerpulse.app"

    func placeholder(in context: Context) -> LedgerPulseEntry {
        LedgerPulseEntry(
            date: Date(),
            companyName: "Ledger Enterprise",
            companyId: "default",
            currencySymbol: "₹",
            cashInAmount: "2000",
            cashOutAmount: "1000",
            lastSyncTimestamp: ISO8601DateFormatter().string(from: Date()),
            isPreview: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerPulseEntry) -> Void) {
        let entry = loadEntry(isPreview: context.isPreview)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerPulseEntry>) -> Void) {
        let currentEntry = loadEntry(isPreview: false)
        // Refresh every 15 minutes or when triggered by Flutter HomeWidget.updateWidget
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry(isPreview: Bool) -> LedgerPulseEntry {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        let companyName = userDefaults?.string(forKey: "company_name") ?? "Ledger Enterprise"
        let companyId = userDefaults?.string(forKey: "company_id") ?? "default"
        let currencySymbol = userDefaults?.string(forKey: "currency_symbol") ?? "₹"
        
        var cashIn = userDefaults?.string(forKey: "cash_in_value")
        if cashIn == nil || cashIn?.isEmpty == true {
            let fullIn = userDefaults?.string(forKey: "cash_in_amount") ?? "2000"
            cashIn = fullIn.replacingOccurrences(of: "₹", with: "").trimmingCharacters(in: .whitespaces)
        }

        var cashOut = userDefaults?.string(forKey: "cash_out_value")
        if cashOut == nil || cashOut?.isEmpty == true {
            let fullOut = userDefaults?.string(forKey: "cash_out_amount") ?? "1000"
            cashOut = fullOut.replacingOccurrences(of: "₹", with: "").trimmingCharacters(in: .whitespaces)
        }

        let timestamp = userDefaults?.string(forKey: "last_sync_timestamp") ?? ISO8601DateFormatter().string(from: Date())

        return LedgerPulseEntry(
            date: Date(),
            companyName: companyName,
            companyId: companyId,
            currencySymbol: currencySymbol,
            cashInAmount: cashIn ?? "2000",
            cashOutAmount: cashOut ?? "1000",
            lastSyncTimestamp: timestamp,
            isPreview: isPreview
        )
    }
}

// MARK: - Main Widget View
struct LedgerPulseWidgetEntryView: View {
    var entry: LedgerPulseTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry, colorScheme: colorScheme)
            case .systemMedium:
                MediumWidgetView(entry: entry, colorScheme: colorScheme)
            default:
                SmallWidgetView(entry: entry, colorScheme: colorScheme)
            }
        }
        .widgetURL(URL(string: "ledgerpulse://dashboard?company_id=\(entry.companyId)"))
    }
}

// MARK: - Small Form Factor View (Matches prompt reference image)
struct SmallWidgetView: View {
    let entry: LedgerPulseEntry
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.10, green: 0.14, blue: 0.11)
        } else {
            // Refined Sage-Mint tone matching the prompt image
            return Color(red: 0.61, green: 0.84, blue: 0.64)
        }
    }

    private var textColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.90, green: 0.94, blue: 0.90)
        } else {
            return Color(red: 0.05, green: 0.12, blue: 0.07)
        }
    }

    private var dividerColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.22, green: 0.30, blue: 0.24)
        } else {
            return Color(red: 0.32, green: 0.45, blue: 0.34)
        }
    }

    var body: some View {
        ZStack {
            backgroundColor

            VStack(alignment: .leading, spacing: 0) {
                // Header: Company Name
                Text(entry.companyName)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 14)
                    .padding(.horizontal, 16)

                Spacer(minLength: 4)

                // Metric 1: Cash In / Receivable / You'll Get (↓ ₹ 2000)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(textColor)

                    Text(entry.currencySymbol)
                        .font(.system(size: 24, weight: .regular, design: .default))
                        .foregroundColor(textColor)

                    Text(entry.cashInAmount)
                        .font(.system(size: 32, weight: .light, design: .default))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 4)

                // Structural Divider
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                Spacer(minLength: 4)

                // Metric 2: Cash Out / Payable / You'll Give (↑ ₹ 1000)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(textColor)

                    Text(entry.currencySymbol)
                        .font(.system(size: 24, weight: .regular, design: .default))
                        .foregroundColor(textColor)

                    Text(entry.cashOutAmount)
                        .font(.system(size: 32, weight: .light, design: .default))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 12)
            }
        }
    }
}

// MARK: - Medium Form Factor View
struct MediumWidgetView: View {
    let entry: LedgerPulseEntry
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.10, green: 0.14, blue: 0.11)
        } else {
            return Color(red: 0.61, green: 0.84, blue: 0.64)
        }
    }

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.15, green: 0.22, blue: 0.17)
        } else {
            return Color(red: 0.52, green: 0.77, blue: 0.56)
        }
    }

    private var textColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.90, green: 0.94, blue: 0.90)
        } else {
            return Color(red: 0.05, green: 0.12, blue: 0.07)
        }
    }

    private var subtitleColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.65, green: 0.75, blue: 0.66)
        } else {
            return Color(red: 0.18, green: 0.32, blue: 0.20)
        }
    }

    var body: some View {
        ZStack {
            backgroundColor

            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.companyName)
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        Text("LIVE LEDGER PULSE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(subtitleColor)
                    }

                    Spacer()

                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(textColor.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Dual Metric Cards
                HStack(spacing: 10) {
                    // You'll Get Card (Down Arrow)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? .green : Color(red: 0.0, green: 0.35, blue: 0.15))

                            Text("YOU'LL GET")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(subtitleColor)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(entry.currencySymbol)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(textColor)

                            Text(entry.cashInAmount)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackgroundColor)
                    .cornerRadius(14)

                    // You'll Give Card (Up Arrow)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? .red : Color(red: 0.55, green: 0.10, blue: 0.10))

                            Text("YOU'LL GIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(subtitleColor)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(entry.currencySymbol)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(textColor)

                            Text(entry.cashOutAmount)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackgroundColor)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Widget Configuration
struct LedgerPulseWidget: Widget {
    let kind: String = "LedgerPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerPulseTimelineProvider()) { entry in
            LedgerPulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ledger Pulse")
        .description("Real-time Cash In and Cash Out metrics for your active company.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews
struct LedgerPulseWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LedgerPulseWidgetEntryView(
                entry: LedgerPulseEntry(
                    date: Date(),
                    companyName: "Ledger Enterprise",
                    companyId: "default",
                    currencySymbol: "₹",
                    cashInAmount: "2000",
                    cashOutAmount: "1000",
                    lastSyncTimestamp: "",
                    isPreview: true
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small Light")

            LedgerPulseWidgetEntryView(
                entry: LedgerPulseEntry(
                    date: Date(),
                    companyName: "Ledger Enterprise",
                    companyId: "default",
                    currencySymbol: "₹",
                    cashInAmount: "2000",
                    cashOutAmount: "1000",
                    lastSyncTimestamp: "",
                    isPreview: true
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .preferredColorScheme(.dark)
            .previewDisplayName("Small Dark")

            LedgerPulseWidgetEntryView(
                entry: LedgerPulseEntry(
                    date: Date(),
                    companyName: "Ledger Enterprise",
                    companyId: "default",
                    currencySymbol: "₹",
                    cashInAmount: "2000",
                    cashOutAmount: "1000",
                    lastSyncTimestamp: "",
                    isPreview: true
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Medium Light")
        }
    }
}
