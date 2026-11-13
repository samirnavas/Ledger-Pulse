import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct LedgerPulseEntry: TimelineEntry {
    let date: Date
    let companyName: String
    let companyId: String
    let currencySymbol: String
    let mode: String
    let spendLabel: String
    let cashInAmount: String
    let cashOutAmount: String
    let todaySpendAmount: String
    let spendProgressText: String
    let spendPercentText: String
    let spendProgressPercent: Double
    let category1Name: String
    let category2Name: String
    let category3Name: String
    let category1Percent: Double
    let category2Percent: Double
    let category3Percent: Double
    let lastSyncTimestamp: String
    let isPreview: Bool

    var isExpense: Bool {
        let m = mode.lowercased()
        return m == "expense" || m == "expensetracker" || m == "expense_tracker"
    }
}

// MARK: - Timeline Provider
struct LedgerPulseTimelineProvider: TimelineProvider {
    typealias Entry = LedgerPulseEntry
    private let appGroupId = "group.com.ledgerpulse.app"

    func placeholder(in context: Context) -> LedgerPulseEntry {
        LedgerPulseEntry(
            date: Date(),
            companyName: "Profile Name",
            companyId: "default",
            currencySymbol: "₹",
            mode: "expense",
            spendLabel: "Today",
            cashInAmount: "2000",
            cashOutAmount: "1000",
            todaySpendAmount: "₹2,000",
            spendProgressText: "Spend - 2000/3700",
            spendPercentText: "58%",
            spendProgressPercent: 58.0,
            category1Name: "Food & Dining",
            category2Name: "Groceries",
            category3Name: "Travel",
            category1Percent: 45.0,
            category2Percent: 30.0,
            category3Percent: 25.0,
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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry(isPreview: Bool) -> LedgerPulseEntry {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        let companyName = userDefaults?.string(forKey: "company_name") ?? "Profile Name"
        let companyId = userDefaults?.string(forKey: "company_id") ?? "default"
        let currencySymbol = userDefaults?.string(forKey: "currency_symbol") ?? "₹"
        let mode = userDefaults?.string(forKey: "mode") ?? "ledger"

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

        var todaySpend = userDefaults?.string(forKey: "today_spend_amount")
        if todaySpend == nil || todaySpend?.isEmpty == true {
            let val = userDefaults?.string(forKey: "today_spend_value") ?? "2,000"
            todaySpend = "\(currencySymbol)\(val)"
        }

        let spendProgress = userDefaults?.string(forKey: "spend_progress_text") ?? "Spend - 2000/3700"
        let spendPercent = userDefaults?.string(forKey: "spend_percent_text") ?? "58%"
        let progressInt = Double(userDefaults?.integer(forKey: "spend_progress_percent") ?? 58)

        let cat1 = userDefaults?.string(forKey: "category_1_name") ?? "Food & Dining"
        let cat2 = userDefaults?.string(forKey: "category_2_name") ?? "Groceries"
        let cat3 = userDefaults?.string(forKey: "category_3_name") ?? "Travel"

        let p1 = userDefaults?.double(forKey: "category_1_percent") ?? 45.0
        let p2 = userDefaults?.double(forKey: "category_2_percent") ?? 30.0
        let p3 = userDefaults?.double(forKey: "category_3_percent") ?? 25.0
        let spendLabel = userDefaults?.string(forKey: "spend_label")
            ?? userDefaults?.string(forKey: "today_label")
            ?? "Today"

        let timestamp = userDefaults?.string(forKey: "last_sync_timestamp") ?? ISO8601DateFormatter().string(from: Date())

        return LedgerPulseEntry(
            date: Date(),
            companyName: companyName,
            companyId: companyId,
            currencySymbol: currencySymbol,
            mode: mode,
            spendLabel: spendLabel,
            cashInAmount: cashIn ?? "2000",
            cashOutAmount: cashOut ?? "1000",
            todaySpendAmount: todaySpend ?? "₹2,000",
            spendProgressText: spendProgress,
            spendPercentText: spendPercent,
            spendProgressPercent: progressInt,
            category1Name: cat1,
            category2Name: cat2,
            category3Name: cat3,
            category1Percent: p1 > 0 ? p1 : 45.0,
            category2Percent: p2 > 0 ? p2 : 30.0,
            category3Percent: p3 > 0 ? p3 : 25.0,
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
            if entry.isExpense {
                switch family {
                case .systemSmall:
                    SmallExpenseWidgetView(entry: entry, colorScheme: colorScheme)
                case .systemMedium:
                    MediumExpenseWidgetView(entry: entry, colorScheme: colorScheme)
                default:
                    SmallExpenseWidgetView(entry: entry, colorScheme: colorScheme)
                }
            } else {
                switch family {
                case .systemSmall:
                    SmallWidgetView(entry: entry, colorScheme: colorScheme)
                case .systemMedium:
                    MediumWidgetView(entry: entry, colorScheme: colorScheme)
                default:
                    SmallWidgetView(entry: entry, colorScheme: colorScheme)
                }
            }
        }
        .widgetURL(URL(string: "ledgerpulse://dashboard?company_id=\(entry.companyId)"))
    }
}

// MARK: - Small Expense Tracker View (Matches Image 1)
struct SmallExpenseWidgetView: View {
    let entry: LedgerPulseEntry
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.09, green: 0.14, blue: 0.10)
        } else {
            return Color(red: 0.61, green: 0.83, blue: 0.60) // #9CD499
        }
    }

    private var textColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.89, green: 0.93, blue: 0.89)
        } else {
            return Color(red: 0.11, green: 0.26, blue: 0.11) // #1D431B
        }
    }

    private var trackColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.16, green: 0.26, blue: 0.18)
        } else {
            return Color(red: 0.76, green: 0.92, blue: 0.75) // #C2EAC0
        }
    }

    private var fillColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.40, green: 0.73, blue: 0.42)
        } else {
            return Color(red: 0.27, green: 0.45, blue: 0.27) // #467244
        }
    }

    var body: some View {
        ZStack {
            backgroundColor

            VStack(alignment: .leading, spacing: 0) {
                // Header: Profile Name (left) & Wallet Icon (right)
                HStack(alignment: .center) {
                    Text(entry.companyName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(textColor)
                        .lineLimit(1)

                    Spacer()

                    Link(destination: URL(string: "ledgerpulse://dashboard?company_id=\(entry.companyId)&action=quick_add")!) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(textColor)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer()

                // Subtitle: Today or This Month
                Text(entry.spendLabel)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 16)

                // Large Amount: ₹2,000
                Text(entry.todaySpendAmount)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)

                Spacer()

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(trackColor)
                            .frame(height: 10)

                        Capsule()
                            .fill(fillColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(entry.spendProgressPercent / 100.0))), height: 10)
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 16)

                // Spend status row: Spend - 2000/3700 & 58%
                HStack {
                    Text(entry.spendProgressText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(textColor)
                        .lineLimit(1)

                    Spacer()

                    Text(entry.spendPercentText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(textColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Medium Expense Tracker View (Matches Image 2)
struct MediumExpenseWidgetView: View {
    let entry: LedgerPulseEntry
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.09, green: 0.14, blue: 0.10)
        } else {
            return Color(red: 0.61, green: 0.83, blue: 0.60) // #9CD499
        }
    }

    private var textColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.89, green: 0.93, blue: 0.89)
        } else {
            return Color(red: 0.11, green: 0.26, blue: 0.11) // #1D431B
        }
    }

    private var trackColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.16, green: 0.26, blue: 0.18)
        } else {
            return Color(red: 0.76, green: 0.92, blue: 0.75) // #C2EAC0
        }
    }

    private var fillColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.40, green: 0.73, blue: 0.42)
        } else {
            return Color(red: 0.27, green: 0.45, blue: 0.27) // #467244
        }
    }

    var body: some View {
        ZStack {
            backgroundColor

            HStack(spacing: 12) {
                // Left Column: Metrics & Progress
                VStack(alignment: .leading, spacing: 0) {
                    // Header: Profile Name with Wallet Icon right next to it
                    HStack(spacing: 6) {
                        Text(entry.companyName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        WalletIconView(color: textColor, size: 18)
                    }
                    .padding(.top, 14)

                    Spacer()

                    Text(entry.spendLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(textColor)

                    Text(entry.todaySpendAmount)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)

                    Spacer()

                    // Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(trackColor)
                                .frame(height: 8)

                            Capsule()
                                .fill(fillColor)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(entry.spendProgressPercent / 100.0))), height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Spend status
                    HStack {
                        Text(entry.spendProgressText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        Spacer()

                        Text(entry.spendPercentText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(textColor)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right Column: Add Button, Donut Chart & Category Legend
                VStack(alignment: .center, spacing: 4) {
                    // Plus action button
                    HStack {
                        Spacer()
                        Link(destination: URL(string: "ledgerpulse://dashboard?company_id=\(entry.companyId)&action=quick_add")!) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(textColor)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 4)

                    // Donut Chart
                    ZStack {
                        DonutChartView(
                            percentages: [entry.category1Percent, entry.category2Percent, entry.category3Percent],
                            colorScheme: colorScheme
                        )
                        .frame(width: 68, height: 68)

                        // Center Pie Chart Icon
                        PieChartIconView(color: textColor, size: 20)
                    }

                    // Legend
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(entry.category1Name)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        Text("• \(entry.category2Name)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        Text("• \(entry.category3Name)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 12)
                }
                .frame(width: 120)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Reusable Wallet Icon
struct WalletIconView: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(color, lineWidth: size * 0.12)
                .frame(width: size, height: size * 0.8)

            // Inner Flap with snap dot
            HStack(spacing: 0) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.1)
                        .fill(color)
                        .frame(width: size * 0.42, height: size * 0.35)

                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: size * 0.12, height: size * 0.12)
                }
            }
            .frame(width: size, height: size * 0.8)
        }
    }
}

// MARK: - Reusable Center Pie Icon
struct PieChartIconView: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)

            // Cross divider
            Rectangle()
                .fill(Color(red: 0.61, green: 0.83, blue: 0.60))
                .frame(width: 2, height: size)

            Rectangle()
                .fill(Color(red: 0.61, green: 0.83, blue: 0.60))
                .frame(width: size, height: 2)
        }
    }
}

// MARK: - Donut Chart View
struct DonutChartView: View {
    let percentages: [Double]
    let colorScheme: ColorScheme

    private var sliceColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.51, green: 0.78, blue: 0.52),
                Color(red: 0.30, green: 0.69, blue: 0.31),
                Color(red: 0.18, green: 0.49, blue: 0.20)
            ]
        } else {
            return [
                Color(red: 0.05, green: 0.20, blue: 0.05), // #0E340C
                Color(red: 0.27, green: 0.45, blue: 0.27), // #467244
                Color(red: 0.76, green: 0.92, blue: 0.75)  // #C2EAC0
            ]
        }
    }

    var body: some View {
        let total = percentages.reduce(0, +)
        let normalized = total > 0 ? percentages.map { $0 / total } : [0.45, 0.30, 0.25]
        let p1 = normalized[0]
        let p2 = normalized.count > 1 ? normalized[1] : 0.3
        let p3 = normalized.count > 2 ? normalized[2] : 0.25

        ZStack {
            // Slice 1
            Circle()
                .trim(from: 0.01, to: max(0.01, CGFloat(p1) - 0.01))
                .stroke(sliceColors[0], style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            // Slice 2
            Circle()
                .trim(from: CGFloat(p1) + 0.01, to: max(CGFloat(p1) + 0.01, CGFloat(p1 + p2) - 0.01))
                .stroke(sliceColors[1], style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            // Slice 3
            Circle()
                .trim(from: CGFloat(p1 + p2) + 0.01, to: 0.99)
                .stroke(sliceColors[2], style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Small Form Factor View (Ledger Mode)
struct SmallWidgetView: View {
    let entry: LedgerPulseEntry
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.10, green: 0.14, blue: 0.11)
        } else {
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

// MARK: - Medium Form Factor View (Ledger Mode)
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
        .description("Real-time metrics and expense tracking for your active company.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
