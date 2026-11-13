// OpenCode Monitor — macOS 菜单栏应用
// 监控 OpenCode Console 的模型用量（额度 / 花费 / token / 逐日趋势 / 请求明细）
// 数据源：opencode.ai/console/api（官方网页版同款接口，API Key 认证）

import AppKit
import Foundation

// MARK: - 深色系配色（可读性优先，避免系统亮色太浅）
let cBlue   = NSColor(red: 0.08, green: 0.27, blue: 0.56, alpha: 1)   // 深蓝
let cGreen  = NSColor(red: 0.00, green: 0.42, blue: 0.23, alpha: 1)   // 深绿
let cOrange = NSColor(red: 0.64, green: 0.31, blue: 0.00, alpha: 1)   // 深橙
let cPurple = NSColor(red: 0.36, green: 0.16, blue: 0.54, alpha: 1)   // 深紫
let cRed    = NSColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)   // 深红
let cTeal   = NSColor(red: 0.00, green: 0.36, blue: 0.38, alpha: 1)   // 深青
let cPink   = NSColor(red: 0.60, green: 0.10, blue: 0.30, alpha: 1)   // 深玫红
let cIndigo = NSColor(red: 0.24, green: 0.22, blue: 0.50, alpha: 1)   // 深靛蓝
let cBrown  = NSColor(red: 0.40, green: 0.24, blue: 0.10, alpha: 1)   // 深棕
let cMint   = NSColor(red: 0.00, green: 0.40, blue: 0.26, alpha: 1)   // 深薄荷绿

// MARK: - Go 官方每模型月额度（USD，来源 opencode.ai/docs/go「Usage limits」）
// 文档口径：每个模型有独立月额度，5 小时 = 20%、每周 = 50%、每月 = 100%
let goMonthlyLimits: [String: Double] = [
    "glm-5.3-flash": 60, "glm-5.3": 15, "glm-5.2": 60,
    "kimi-k3.1-pro": 15, "kimi-k3": 15, "kimi-k2.7-code": 60,
    "longcat-2.0": 60, "step-5-preview": 15,
    "mimo-v2.6-flash": 60, "mimo-v2.6-pro": 15, "mimo-v2.5": 60, "mimo-v2.5-pro": 15,
    "minimax-m3.1-flash": 20, "minimax-m3": 60,
    "muse-spark-1.3-contributor": 60, "muse-spark-1.2-contributor": 60,
    "qwen3.8-max": 15, "qwen3.8-flash": 30, "qwen3.7-plus": 60,
    "deepseek-v4.1-flash": 100, "deepseek-v4-pro": 15,
    "hy4": 60, "hy4-preview": 30, "hy3": 60,
    "grok-4.7": 15, "gpt-6-luna": 15, "gpt-5.6-luna": 15,
    "claude-haiku-5-5": 15, "gemini-4-argon": 30,
]

// Go Plus 档（官方页面公布的子集，未收录的模型回退到账户计量，避免误报）
let goPlusMonthlyLimits: [String: Double] = [
    "glm-5.3-flash": 180, "kimi-k3": 60, "mimo-v2.6-flash": 120,
    "deepseek-v4.1-flash": 200, "claude-haiku-5-5": 60, "minimax-m3.1-flash": 80,
]

// MARK: - API 数据模型（接口返回的数字大多是字符串）

struct SummaryResp: Codable {
    var totalRequests: String?
    var totalInputTokens: String?
    var totalOutputTokens: String?
    var totalCacheReadTokens: String?
    var totalCacheWrite5mTokens: String?
    var totalCacheWrite1hTokens: String?
    var totalCostMicroCents: String?
}

struct ModelItem: Codable {
    var model: String?
    var provider: String?
    var totalRequests: String?
    var totalInputTokens: String?
    var totalOutputTokens: String?
    var totalCacheReadTokens: String?
    var totalCostMicroCents: String?
}

struct ModelsResp: Codable { var items: [ModelItem]? }

struct GoDaily: Codable {
    var date: String?
    var totalCostMicroCents: String?
    var totalTokens: String?
    var totalRequests: String?
}

struct GoModelUse: Codable {
    var provider: String?
    var model: String?
    var totalRequests: String?
}

struct GoResp: Codable {
    var startsAt: String?
    var daily: [GoDaily]?
    var models: [GoModelUse]?
}

struct GoMeter: Codable {
    var startsAt: String?
    var resetsAt: String?
    var limitMicroCents: String?
    var usedMicroCents: String?
}

struct GoMeters: Codable {
    var fiveHour: GoMeter?
    var week: GoMeter?
    var month: GoMeter?
}

struct GoAccess: Codable {
    var startsAt: String?
    var endsAt: String?
    var meters: GoMeters?
}

struct GoStatusResp: Codable {
    var product: String?
    var renewalProduct: String?
    var paymentMethodKind: String?
    var renewalCurrency: String?
    var cancelAtPeriodEnd: Bool?
    var access: GoAccess?
    var upgradePrice: GoPrice?
    var teamsUpgradePrice: GoPrice?
}

struct GoPrice: Codable {
    var amountMicroCents: String?
    var currency: String?
    var memberCount: Int?
}

/// 单条推理请求日志
struct RequestLog: Decodable {
    var startedAt: Int64?
    var finishedAt: Int64?
    var durationMs: Int64?
    var outcome: String?
    var statusCode: Int?
    var model: String?
    var provider: String?
    var app: String?
    var sessionID: String?
    var timeToFirstTokenMs: Int64?
    var inputTokens: Int64?
    var outputTokens: Int64?
    var reasoningTokens: Int64?
    var cacheReadTokens: Int64?
    var cacheWriteTokens: Int64?
    var cost: Double?
    var errorCode: String?
    var errorMessage: String?
    var finishReason: String?
    var attemptCount: Int?

    enum CodingKeys: String, CodingKey {
        case startedAt, finishedAt, durationMs, outcome, statusCode, model, provider, app
        case sessionID, timeToFirstTokenMs, inputTokens, outputTokens, reasoningTokens
        case cacheReadTokens, cacheWriteTokens, cost, errorCode, errorMessage, attemptCount
        case finish
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try? c.decode(Int64.self, forKey: .startedAt)
        finishedAt = try? c.decode(Int64.self, forKey: .finishedAt)
        durationMs = try? c.decode(Int64.self, forKey: .durationMs)
        outcome = try? c.decode(String.self, forKey: .outcome)
        statusCode = try? c.decode(Int.self, forKey: .statusCode)
        model = try? c.decode(String.self, forKey: .model)
        provider = try? c.decode(String.self, forKey: .provider)
        app = try? c.decode(String.self, forKey: .app)
        sessionID = try? c.decode(String.self, forKey: .sessionID)
        timeToFirstTokenMs = try? c.decode(Int64.self, forKey: .timeToFirstTokenMs)
        inputTokens = try? c.decode(Int64.self, forKey: .inputTokens)
        outputTokens = try? c.decode(Int64.self, forKey: .outputTokens)
        reasoningTokens = try? c.decode(Int64.self, forKey: .reasoningTokens)
        cacheReadTokens = try? c.decode(Int64.self, forKey: .cacheReadTokens)
        cacheWriteTokens = try? c.decode(Int64.self, forKey: .cacheWriteTokens)
        cost = try? c.decode(Double.self, forKey: .cost)
        errorCode = try? c.decode(String.self, forKey: .errorCode)
        errorMessage = try? c.decode(String.self, forKey: .errorMessage)
        attemptCount = try? c.decode(Int.self, forKey: .attemptCount)
        // finish 嵌套对象：{reason: "tool_calls"}
        if let f = try? c.decode([String: String].self, forKey: .finish) {
            finishReason = f["reason"]
        }
    }
}

struct RequestLogsResp: Decodable {
    var items: [RequestLog]?
    var retentionDays: Int?
    var nextCursor: String?
}

/// 单个小时桶（本地时区）：费用 / 请求数 / token 总量（输入+输出+思考）
struct HourBucket {
    let date: Date
    var cost: Double = 0
    var requests: Int64 = 0
    var tokens: Int64 = 0
}

struct Config: Codable {
    var apiKey: String
    var refreshIntervalSeconds: Int?
    var consoleURL: String?
    /// 接口根地址（可改，默认 https://opencode.ai/console/api）
    var apiBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case apiKey, refreshIntervalSeconds, consoleURL, apiBaseURL
    }

    init(apiKey: String, refreshIntervalSeconds: Int? = nil,
         consoleURL: String? = nil, apiBaseURL: String? = nil) {
        self.apiKey = apiKey
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.consoleURL = consoleURL
        self.apiBaseURL = apiBaseURL
    }

    /// 容错解析：缺字段不至于整份配置报废
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
        refreshIntervalSeconds = try? c.decode(Int.self, forKey: .refreshIntervalSeconds)
        consoleURL = try? c.decode(String.self, forKey: .consoleURL)
        apiBaseURL = try? c.decode(String.self, forKey: .apiBaseURL)
    }
}

// MARK: - 格式化

func toInt(_ s: String?) -> Int64 {
    guard let s, let v = Int64(s) else { return 0 }
    return v
}

func fmtCost(_ microCents: String?) -> String {
    let v = Double(toInt(microCents)) / 100_000_000
    if v == 0 { return "$0" }
    if abs(v) < 0.01 { return String(format: "$%.4f", v) }
    return String(format: "$%.2f", v)
}

func fmtUSD(_ v: Double) -> String {
    if v == 0 { return "$0" }
    if abs(v) < 0.01 { return String(format: "$%.4f", v) }
    return String(format: "$%.2f", v)
}

func fmtTokens(_ s: String?) -> String { fmtTokens(toInt(s)) }

func fmtTokens(_ v: Int64) -> String {
    if v >= 1_000_000_000 { return String(format: "%.2fB", Double(v) / 1e9) }
    if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
    if v >= 1_000 { return String(format: "%.1fK", Double(v) / 1e3) }
    return String(v)
}

func fmtCount(_ s: String?) -> String { fmtCount(toInt(s)) }

func fmtCount(_ v: Int64) -> String {
    if v >= 10_000 { return String(format: "%.1f万", Double(v) / 10_000) }
    return String(v)
}

func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    return f2.date(from: s)
}

func fmtDuration(_ interval: TimeInterval) -> String {
    let total = Int(max(0, interval))
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let mins = (total % 3600) / 60
    if days > 0 { return "\(days)天\(hours)小时" }
    if hours > 0 { return "\(hours)小时\(mins)分" }
    return "\(mins)分"
}

func usageFraction(_ m: GoMeter?) -> (fraction: Double, pctText: String, used: Double, limit: Double)? {
    guard let m, let limitStr = m.limitMicroCents, let usedStr = m.usedMicroCents,
          let limit = Double(limitStr), limit > 0, let used = Double(usedStr) else { return nil }
    let f = used / limit
    return (f, String(format: "%.0f%%", f * 100), used, limit)
}

// MARK: - 自定义视图

/// 单条彩色进度条（浅灰底 + 彩色填充）
final class BarView: NSView {
    private let fraction: CGFloat
    private let color: NSColor

    init(width: CGFloat, fraction: CGFloat, color: NSColor) {
        self.fraction = max(0.02, min(1, fraction))
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 9))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4.5, yRadius: 4.5).fill()
        let w = bounds.width * fraction
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 4.5, yRadius: 4.5).fill()
    }
}

/// 模型行：彩色模型名 + 统计 + 右侧同色占比条
final class ModelRowView: NSView {
    /// 两行布局：上行 = 模型名 + 统计；下行 = 占比条 + 备注（如「月额度 $100」）
    init(name: String, stats: String, note: String, fraction: CGFloat, color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 38))

        let title = NSTextField(labelWithString: name)
        title.font = .menuFont(ofSize: 13)
        title.textColor = color
        title.frame = NSRect(x: 12, y: 20, width: 200, height: 18)
        title.lineBreakMode = .byTruncatingMiddle
        addSubview(title)

        let value = NSTextField(labelWithString: stats)
        value.font = .menuFont(ofSize: 12)
        value.textColor = .labelColor
        value.alignment = .right
        value.frame = NSRect(x: 180, y: 21, width: 148, height: 16)
        value.lineBreakMode = .byTruncatingTail
        addSubview(value)

        let bar = BarView(width: 208, fraction: fraction, color: color)
        bar.frame.origin = NSPoint(x: 12, y: 8)
        addSubview(bar)

        if !note.isEmpty {
            let noteField = NSTextField(labelWithString: note)
            noteField.font = .menuFont(ofSize: 10.5)
            noteField.textColor = .secondaryLabelColor
            noteField.alignment = .right
            noteField.frame = NSRect(x: 226, y: 8, width: 102, height: 15)
            noteField.lineBreakMode = .byTruncatingTail
            addSubview(noteField)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 额度行：标签 + 百分比 + 金额 + 重置倒计时，下方额度条
final class QuotaRowView: NSView {
    init(label: String, pctText: String, amountText: String, resetText: String,
         fraction: CGFloat, color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 40))

        let title = NSTextField(labelWithString: "\(label)  \(pctText)")
        title.font = .menuFont(ofSize: 12)
        title.textColor = color
        title.frame = NSRect(x: 12, y: 22, width: 190, height: 17)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)

        let reset = NSTextField(labelWithString: resetText)
        reset.font = .menuFont(ofSize: 10.5)
        reset.textColor = .labelColor
        reset.alignment = .right
        reset.frame = NSRect(x: 196, y: 23, width: 132, height: 15)
        addSubview(reset)

        let bar = BarView(width: 208, fraction: fraction, color: color)
        bar.frame.origin = NSPoint(x: 12, y: 9)
        addSubview(bar)

        let amount = NSTextField(labelWithString: amountText)
        amount.font = .menuFont(ofSize: 11)
        amount.textColor = .labelColor
        amount.alignment = .right
        amount.frame = NSRect(x: 226, y: 5, width: 102, height: 16)
        addSubview(amount)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Token 构成分段彩色条
final class SegmentedBarView: NSView {
    private struct Seg { let value: Double; let color: NSColor }
    private let segs: [Seg]

    init(segments: [(value: Double, color: NSColor)], width: CGFloat) {
        self.segs = segments.map { Seg(value: $0.value, color: $0.color) }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 12))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let total = segs.reduce(0) { $0 + $1.value }
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        guard total > 0 else { return }
        var x: CGFloat = 0
        for seg in segs {
            let w = bounds.width * CGFloat(seg.value / total)
            seg.color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: w, height: bounds.height), xRadius: 5, yRadius: 5).fill()
            x += w
        }
    }
}

/// 逐日柱状图（近 N 天）
final class DailyBarChartView: NSView {
    private struct Day { let label: String; let value: Double; let requests: Int64 }
    private let days: [Day]

    init(days: [(label: String, value: Double, requests: Int64)], width: CGFloat) {
        self.days = days.map { Day(label: $0.label, value: $0.value, requests: $0.requests) }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 64))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        let maxV = max(days.map { $0.value }.max() ?? 1, 0.0001)
        let leftInset: CGFloat = 12
        let rightInset: CGFloat = 12
        let labelH: CGFloat = 14
        let countH: CGFloat = 12                       // 顶部预留数值行高
        let maxBarH = max(4, bounds.height - labelH - 3 - countH)
        let usable = bounds.width - leftInset - rightInset
        let slot = usable / CGFloat(days.count)
        let barW = min(30, slot * 0.55)

        for (i, d) in days.enumerated() {
            let x = leftInset + slot * CGFloat(i) + (slot - barW) / 2
            let h = max(2, maxBarH * CGFloat(d.value / maxV))
            let y = labelH + 2
            // 最新一天高亮
            let color: NSColor = i == days.count - 1 ? cBlue : cBlue.withAlphaComponent(0.45)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h), xRadius: 3, yRadius: 3).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.labelColor,
            ]
            let s = NSAttributedString(string: d.label, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: x + (barW - size.width) / 2, y: 0))

            // 数值恒定绘制：柱高已预留数值行空间，不会再被挤掉
            let s2 = NSAttributedString(string: fmtCount(d.requests), attributes: attrs)
            let size2 = s2.size()
            let ty = y + h + 1
            if ty + size2.height <= bounds.height - 0.5 {
                s2.draw(at: NSPoint(x: x + (barW - size2.width) / 2, y: ty))
            }
        }
    }
}

/// 小时柱状图（近 24 小时，每 4 根标一个时间），isToken 决定是否用紫色区分
final class HourlyBarChartView: NSView {
    private struct Hour { let label: String; let value: Double; let showLabel: Bool }
    private let hours: [Hour]
    private let color: NSColor

    init(buckets: [HourBucket], isToken: Bool, width: CGFloat) {
        let f = DateFormatter()
        f.dateFormat = "HH:00"
        var hrs: [Hour] = []
        let maxV = max(buckets.map { isToken ? Double($0.tokens) : $0.cost }.max() ?? 1, 0.0001)
        for (i, b) in buckets.enumerated() {
            let v = isToken ? Double(b.tokens) : b.cost
            hrs.append(Hour(label: f.string(from: b.date),
                            value: v / maxV,
                            showLabel: (buckets.count - 1 - i) % 4 == 0))
        }
        self.hours = hrs
        self.color = isToken ? cPurple : cBlue
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 60))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard !hours.isEmpty else { return }
        let leftInset: CGFloat = 12
        let rightInset: CGFloat = 12
        let labelH: CGFloat = 13
        let maxBarH = max(4, bounds.height - labelH - 4)
        let usable = bounds.width - leftInset - rightInset
        let slot = usable / CGFloat(hours.count)
        let barW = min(14, slot * 0.6)

        for (i, h) in hours.enumerated() {
            let x = leftInset + slot * CGFloat(i) + (slot - barW) / 2
            let bh = max(1.5, maxBarH * CGFloat(h.value))
            let y = labelH + 2
            // 当前小时高亮
            let c: NSColor = i == hours.count - 1 ? color : color.withAlphaComponent(0.45)
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: bh), xRadius: 2, yRadius: 2).fill()

            if h.showLabel {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8.5),
                    .foregroundColor: NSColor.labelColor,
                ]
                let s = NSAttributedString(string: h.label, attributes: attrs)
                let sz = s.size()
                let cx = x + barW / 2
                if cx - sz.width / 2 >= 0, cx + sz.width / 2 <= bounds.width {
                    s.draw(at: NSPoint(x: cx - sz.width / 2, y: 0))
                }
            }
        }
    }
}

/// 纯展示文字行：用自定义视图承载，既不会被 AppKit 灰化，悬停也不会高亮
final class MenuInfoView: NSView {
    init(attributed: NSAttributedString, indent: Int = 0, width: CGFloat = 340) {
        let sz = attributed.size()
        let h = max(18, ceil(sz.height) + 6)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        let tf = NSTextField(labelWithAttributedString: attributed)
        let x = 12 + CGFloat(indent) * 16
        tf.frame = NSRect(x: x, y: (h - ceil(sz.height)) / 2 - 1,
                          width: width - x - 8, height: ceil(sz.height) + 2)
        tf.lineBreakMode = .byTruncatingTail
        addSubview(tf)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 主监控器

final class Monitor: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var config: Config?
    private var summaries: [String: SummaryResp] = [:]
    private var modelsByRange: [String: [ModelItem]] = [:]
    private var goDaily: [GoDaily] = []
    private var goStatus: GoStatusResp?
    private var goMeters: GoMeters?
    private var logs: [RequestLog] = []
    private var hourlyBuckets: [HourBucket] = []
    private var lastUpdated: Date?
    private var lastError: String?
    private var timer: Timer?
    private var refreshing = false

    private let launchAgentLabel = "com.strangewilliam.opencodemonitor"
    private var launchAgentPath: String {
        NSString(string: "~/Library/LaunchAgents/\(launchAgentLabel).plist").expandingTildeInPath
    }

    /// 默认接口根地址 / 网页地址（被配置覆盖时以配置为准）
    static let defaultAPIBase = "https://opencode.ai/console/api"
    static let defaultConsoleURL = "https://opencode.ai/console"

    /// 当前生效的接口根地址（去空白、去尾部斜杠）
    private var apiBase: String {
        var raw = (config?.apiBaseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { raw = Monitor.defaultAPIBase }
        while raw.hasSuffix("/") { raw = String(raw.dropLast()) }
        return raw
    }

    private var consoleURLString: String {
        let raw = (config?.consoleURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? Monitor.defaultConsoleURL : raw
    }

    /// 接口主机名，用于菜单里一眼确认当前指向哪儿
    private var apiHostText: String {
        URL(string: apiBase)?.host ?? apiBase
    }

    /// Key 打码显示（保留末 4 位）
    /// 当前订阅是否 Go Plus
    private var planIsPlus: Bool {
        (goStatus?.product ?? "").lowercased().contains("plus")
    }

    /// 官方文档里该模型的月额度
    private func monthlyLimit(for model: String) -> Double? {
        planIsPlus ? goPlusMonthlyLimits[model] : goMonthlyLimits[model]
    }

    /// 主用模型（30 天花费占比 ≥ 80%）及其官方月额度；混合使用时返回 nil（回退账户计量）
    private func dominantModelQuota() -> (id: String, monthLimit: Double)? {
        guard let list = modelsByRange["30d"], !list.isEmpty else { return nil }
        let items = list.compactMap { m -> (String, Double)? in
            guard let id = m.model else { return nil }
            return (id, Double(toInt(m.totalCostMicroCents)))
        }
        let total = items.reduce(0) { $0 + $1.1 }
        guard total > 0, let top = items.max(by: { $0.1 < $1.1 }),
              top.1 / total >= 0.8, let lim = monthlyLimit(for: top.0) else { return nil }
        return (top.0, lim)
    }

    private var maskedKey: String {
        let k = (config?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { return "未设置" }
        return k.count <= 8 ? String(repeating: "•", count: k.count) : "••••" + String(k.suffix(4))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()
        statusItem.menu = menu
        menu.autoenablesItems = false
        setTitle("OC …")
        rebuildMenu()
        refresh()
        scheduleTimer()
    }

    // MARK: 配置

    private func configPath() -> String {
        NSString(string: "~/Library/Application Support/OpenCodeMonitor/config.json").expandingTildeInPath
    }

    private func loadConfig() {
        let path = configPath()
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        guard FileManager.default.fileExists(atPath: path) else {
            // 首次运行：生成一份默认配置，用户可在「连接设置…」里填 Key
            let defaults = Config(apiKey: "", refreshIntervalSeconds: 300,
                                  consoleURL: Monitor.defaultConsoleURL,
                                  apiBaseURL: Monitor.defaultAPIBase)
            config = defaults
            _ = saveConfigToDisk(defaults)
            lastError = "首次运行，请在「连接设置…」填入 API Key"
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            config = try JSONDecoder().decode(Config.self, from: data)
            logLine("配置已加载 base=\(apiBase) key=\(maskedKey)")
        } catch {
            lastError = "配置文件解析失败：\(error.localizedDescription)（可在「连接设置…」重填）"
        }
    }

    /// 写回配置文件（权限 600，只本人可读）
    @discardableResult
    private func saveConfigToDisk(_ cfg: Config) -> Bool {
        let path = configPath()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(cfg)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            logLine("配置已保存 base=\(cfg.apiBaseURL ?? Monitor.defaultAPIBase) key=\(maskedKey)")
            return true
        } catch {
            lastError = "配置保存失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 日志（排查接口变更用）

    private var logPath: String {
        NSString(string: "~/Library/Logs/OpenCodeMonitor.log").expandingTildeInPath
    }

    private func logLine(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = logPath
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        // 超过 512KB 时滚动一次，避免无限增长
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > 512 * 1024 {
            try? fm.removeItem(atPath: path + ".1")
            try? fm.moveItem(atPath: path, toPath: path + ".1")
        }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: 刷新

    private func scheduleTimer() {
        let interval = TimeInterval(config?.refreshIntervalSeconds ?? 300)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(60, interval), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 分页拉取推理日志：每页 100 条，直到覆盖 cutoff（约 26 小时）或到页数上限
    /// 拉完后聚合为近 24 小时的小时桶（本地时区）
    private func fetchHourlyLogs(base: String, key: String, fail: @escaping (String) -> Void,
                                 completion: @escaping ([RequestLog]) -> Void) {
        var collected: [RequestLog] = []
        var hadError = false
        let cutoff = Date().addingTimeInterval(-26 * 3600).timeIntervalSince1970 * 1000
        let maxPages = 25

        func page(_ cursor: String?, pagesLeft: Int) {
            var comps = URLComponents(string: "\(base)/request-logs")
            var q = [URLQueryItem(name: "category", value: "inference"),
                     URLQueryItem(name: "limit", value: "100")]
            if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
            comps?.queryItems = q
            guard let url = comps?.url else {
                completion(collected)
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "accept")
            URLSession.shared.dataTask(with: req) { data, resp, error in
                if let error { hadError = true; fail("request-logs: \(error.localizedDescription)") }
                guard let data, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let r = try? JSONDecoder().decode(RequestLogsResp.self, from: data),
                      let items = r.items, !items.isEmpty else {
                    if error == nil, !hadError {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        if code != 0 && !(200..<300).contains(code) {
                            fail("request-logs: HTTP \(code)")
                        }
                    }
                    completion(collected)
                    return
                }
                collected += items
                let oldest = items.compactMap { $0.startedAt }.min() ?? 0
                if Double(oldest) < cutoff || pagesLeft <= 1 || r.nextCursor == nil {
                    completion(collected)
                } else {
                    page(r.nextCursor, pagesLeft: pagesLeft - 1)
                }
            }.resume()
        }
        page(nil, pagesLeft: maxPages)
    }

    /// 把日志聚合成近 24 小时的小时桶
    private func aggregateHourly(_ logs: [RequestLog]) -> [HourBucket] {
        let cal = Calendar.current
        let nowHour = cal.dateInterval(of: .hour, for: Date())!.start
        var map: [Date: HourBucket] = [:]
        for i in 0..<24 {
            let h = cal.date(byAdding: .hour, value: -23 + i, to: nowHour)!
            map[h] = HourBucket(date: h)
        }
        let earliest = map.keys.min() ?? nowHour
        for log in logs {
            guard let ts = log.startedAt else { continue }
            let d = Date(timeIntervalSince1970: Double(ts) / 1000)
            guard d >= earliest, let hi = cal.dateInterval(of: .hour, for: d)?.start,
                  var b = map[hi] else { continue }
            b.cost += log.cost ?? 0
            b.requests += 1
            b.tokens += (log.inputTokens ?? 0) + (log.outputTokens ?? 0) + (log.reasoningTokens ?? 0)
            map[hi] = b
        }
        return map.values.sorted { $0.date < $1.date }
    }

    @objc func refresh() {
        let key = (config?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshing, !key.isEmpty else {
            if key.isEmpty { setTitle("OC ⚠️") }
            if config == nil { lastError = config == nil ? "无配置，请打开「连接设置…」" : nil }
            rebuildMenu()
            return
        }
        refreshing = true
        let group = DispatchGroup()
        var newSummaries: [String: SummaryResp] = [:]
        var newModels: [String: [ModelItem]] = [:]
        var newGoDaily: [GoDaily] = []
        var newGoStatus: GoStatusResp?
        var newLogs: [RequestLog] = []
        var apiError: String?
        var okCount = 0
        let lock = NSLock()

        func makeRequest(_ urlStr: String, name: String, handler: @escaping (Data) -> Void) {
            guard let url = URL(string: urlStr) else {
                apiError = "非法 URL: \(urlStr)"
                return
            }
            group.enter()
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "accept")
            URLSession.shared.dataTask(with: req) { data, resp, error in
                defer { group.leave() }
                lock.lock(); defer { lock.unlock() }
                if let error {
                    apiError = apiError ?? "\(name): \(error.localizedDescription)"
                    return
                }
                guard let data, let http = resp as? HTTPURLResponse else {
                    apiError = apiError ?? "\(name): 无响应"
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let hint = http.statusCode == 401 ? "（Key 无效或已失效）"
                        : (http.statusCode == 404 ? "（路径不存在，接口地址可能已变更）" : "")
                    apiError = apiError ?? "\(name): HTTP \(http.statusCode)\(hint)"
                    return
                }
                handler(data)
                okCount += 1
            }.resume()
        }

        let base = apiBase

        for range in ["24h", "7d", "30d"] {
            makeRequest("\(base)/usage/summary?range=\(range)", name: "summary(\(range))") { data in
                if let s = try? JSONDecoder().decode(SummaryResp.self, from: data) {
                    newSummaries[range] = s
                }
            }
            makeRequest("\(base)/usage/models?range=\(range)&page=1&pageSize=20", name: "models(\(range))") { data in
                if let m = try? JSONDecoder().decode(ModelsResp.self, from: data) {
                    newModels[range] = m.items ?? []
                }
            }
        }

        makeRequest("\(base)/activity/go", name: "activity/go") { data in
            if let g = try? JSONDecoder().decode(GoResp.self, from: data) {
                newGoDaily = g.daily ?? []
            }
        }
        makeRequest("\(base)/go/status", name: "go/status") { data in
            if let g = try? JSONDecoder().decode(GoStatusResp.self, from: data) {
                newGoStatus = g
            }
        }
        // 分页拉取推理日志（覆盖近 26 小时），用于小时直方图 + 最近请求 + 请求质量
        group.enter()
        fetchHourlyLogs(base: base, key: key, fail: { msg in
            lock.lock(); apiError = apiError ?? msg; lock.unlock()
        }) { items in
            lock.lock()
            if !items.isEmpty { okCount += 1 }
            newLogs = items
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.refreshing = false
            self.lastError = apiError
            if okCount > 0 {
                self.summaries = newSummaries
                self.modelsByRange = newModels
                self.goDaily = newGoDaily
                self.goStatus = newGoStatus
                self.goMeters = newGoStatus?.access?.meters
                self.logs = newLogs
                self.hourlyBuckets = self.aggregateHourly(newLogs)
                self.lastUpdated = Date()
            }
            if let mq = self.dominantModelQuota() {
                let factor = mq.monthLimit / 60.0
                self.logLine("额度口径：主用模型 \(mq.id) 官方月限 \(fmtUSD(mq.monthLimit))（1 列表价$ = \(String(format: "%.2f", 1 / factor)) allowance，百分比与官网一致）")
            } else {
                self.logLine("额度口径：allowance 计量（无单一主用模型）")
            }
            self.logLine("刷新完成 ok=\(okCount) err=\(apiError ?? "无")")
            self.updateTitle()
            self.rebuildMenu()
        }

        updateTitle()
        rebuildMenu()
    }

    private func updateTitle() {
        if lastError != nil && summaries.isEmpty {
            setTitle("OC ⚠️")
            return
        }
        if refreshing && summaries.isEmpty {
            setTitle("OC …")
            return
        }
        guard let s24 = summaries["24h"] else {
            setTitle("OC ⚠️")
            return
        }
        var title = "OC \(fmtCost(s24.totalCostMicroCents)) · \(fmtCount(s24.totalRequests))次"
        if let m5 = goMeters?.fiveHour, let q = usageFraction(m5) {
            let colorHint = q.fraction >= 0.85 ? "🔴" : (q.fraction >= 0.6 ? "🟠" : "")
            title += " · 5h \(colorHint)\(q.pctText)"
        }
        setTitle(title)
    }

    private func setTitle(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.title = text
        }
    }

    // MARK: 菜单

    private func rebuildMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menu.removeAllItems()

            let palette: [NSColor] = [cBlue, cOrange, cPurple, cTeal,
                                      cPink, cIndigo, cBrown, cMint]

            /// 纯展示行：自定义视图承载，不灰化、不悬停高亮
            func infoItem(_ attributed: NSAttributedString, indent: Int = 0, into target: NSMenu? = nil) {
                let item = NSMenuItem()
                item.view = MenuInfoView(attributed: attributed, indent: indent)
                (target ?? self.menu).addItem(item)
            }

            func coloredText(_ parts: [(String, NSColor?)], indent: Int = 0, into target: NSMenu? = nil) {
                let str = NSMutableAttributedString()
                let f = NSFont.menuFont(ofSize: 13)
                for (text, color) in parts {
                    str.append(NSAttributedString(string: text, attributes: [
                        .font: f, .foregroundColor: color ?? .labelColor,
                    ]))
                }
                infoItem(str, indent: indent, into: target)
            }

            /// 子菜单必须关掉自动启用，否则无 action 的信息行会被 AppKit 强制灰化
            func makeMenu() -> NSMenu {
                let m = NSMenu()
                m.autoenablesItems = false
                return m
            }

            func sep(_ target: NSMenu? = nil) {
                (target ?? self.menu).addItem(.separator())
            }

            func addAction(_ title: String, action: Selector, key: String, state: NSControl.StateValue = .off) {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.target = action == #selector(NSApplication.terminate(_:)) ? nil : self
                item.state = state
                self.menu.addItem(item)
            }

            // 标题
            infoItem(NSAttributedString(string: "OpenCode 用量监控", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]))
            sep()

            if let err = lastError, summaries.isEmpty {
                coloredText([("⚠️ \(err)", cRed)])
                coloredText([("当前接口：\(apiBase)", NSColor.secondaryLabelColor)], indent: 1)
                coloredText([("若接口地址已变更 → 菜单「连接设置…」修改", NSColor.secondaryLabelColor)], indent: 1)
                sep()
            }

            // 1) 三档汇总（花费为列表价口径）
            for (range, label) in [("24h", "今日（0 点起）"), ("7d", "近 7 天（含今日）"), ("30d", "近 30 天（含今日）")] {
                if let s = summaries[range] {
                    coloredText([
                        (label + "    ", .labelColor),
                        ("\(fmtCount(s.totalRequests)) 次", cBlue),
                        (" · ", .labelColor),
                        (fmtCost(s.totalCostMicroCents), cGreen),
                        ("（列表价）", NSColor.secondaryLabelColor),
                    ])
                    coloredText([
                        ("输入 \(fmtTokens(s.totalInputTokens)) · 输出 \(fmtTokens(s.totalOutputTokens)) · 缓存读 \(fmtTokens(s.totalCacheReadTokens)) tok", NSColor.labelColor),
                    ], indent: 1)
                }
            }

            // 2) Token 构成（24h）
            if let s24 = summaries["24h"] {
                let input = Double(toInt(s24.totalInputTokens))
                let output = Double(toInt(s24.totalOutputTokens))
                let cache = Double(toInt(s24.totalCacheReadTokens))
                let cw5 = Double(toInt(s24.totalCacheWrite5mTokens))
                let cw1 = Double(toInt(s24.totalCacheWrite1hTokens))
                if input + output + cache + cw5 + cw1 > 0 {
                    sep()
                    infoItem(NSAttributedString(string: "Token 构成（今日）", attributes: [
                        .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                    ]))
                    let segItem = NSMenuItem()
                    segItem.view = SegmentedBarView(segments: [
                        (cache, cBlue), (input, cPurple), (output, cOrange),
                    ], width: 316)
                    self.menu.addItem(segItem)
                    coloredText([
                        ("■ 缓存 ", cBlue), (fmtTokens(s24.totalCacheReadTokens), .labelColor),
                        ("   ■ 输入 ", cPurple), (fmtTokens(s24.totalInputTokens), .labelColor),
                        ("   ■ 输出 ", cOrange), (fmtTokens(s24.totalOutputTokens), .labelColor),
                    ], indent: 1)
                }
            }

            // 3) 逐日趋势（activity/go，覆盖整个计费周期）
            if goDaily.count > 0 {
                sep()
                infoItem(NSAttributedString(string: "每日用量（计费周期内 \(goDaily.count) 天）", attributes: [
                    .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                ]))
                let recent = Array(goDaily.suffix(14))
                let chartItem = NSMenuItem()
                chartItem.view = DailyBarChartView(
                    days: recent.map { d in
                        let label = String((d.date ?? "").suffix(5))   // MM-DD
                        return (label, Double(toInt(d.totalCostMicroCents)) / 1e8, toInt(d.totalRequests))
                    },
                    width: 316
                )
                self.menu.addItem(chartItem)

                // 每日明细子菜单（完整列表）
                let dailyParent = NSMenuItem(title: "每日明细（\(goDaily.count) 天）", action: nil, keyEquivalent: "")
                let dailySub = makeMenu()
                dailyParent.submenu = dailySub
                self.menu.addItem(dailyParent)
                for d in goDaily.reversed() {
                    coloredText([
                        (d.date ?? "—", .labelColor), ("    ", .labelColor),
                        ("\(fmtCount(d.totalRequests)) 次", cBlue),
                        (" · " + fmtTokens(d.totalTokens) + " tok", .labelColor),
                        (" · ", .labelColor),
                        (fmtCost(d.totalCostMicroCents), cGreen),
                    ], into: dailySub)
                }
            }

            // 3.5) 小时直方图（近 24 小时，由逐条推理日志聚合，与网页 Hourly Cost 同源同形）
            if hourlyBuckets.count == 24 {
                sep()
                let totalCost = hourlyBuckets.reduce(0) { $0 + $1.cost }
                let totalReq = hourlyBuckets.reduce(0) { $0 + $1.requests }
                let peak = hourlyBuckets.max { a, b in
                    a.cost == b.cost ? a.requests < b.requests : a.cost < b.cost
                }
                var peakText = ""
                if let peak, peak.cost > 0 {
                    let f = DateFormatter()
                    f.dateFormat = "HH:00"
                    peakText = " · 峰值 \(f.string(from: peak.date)) \(fmtUSD(peak.cost))"
                }
                infoItem(NSAttributedString(string: "小时用量（滚动 24 小时 · 共\(fmtCount(totalReq))次 \(fmtUSD(totalCost))\(peakText)）", attributes: [
                    .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                ]))

                let costChart = NSMenuItem()
                costChart.view = HourlyBarChartView(buckets: hourlyBuckets, isToken: false, width: 316)
                self.menu.addItem(costChart)

                let tokChart = NSMenuItem()
                tokChart.view = HourlyBarChartView(buckets: hourlyBuckets, isToken: true, width: 316)
                self.menu.addItem(tokChart)

                // 图例
                coloredText([
                    ("■ Cost", cBlue), ("  ", .labelColor), ("■ Tokens（输入+输出+思考）", cPurple),
                ], indent: 1)
            }

            // 4) Go 额度（allowance 计量，与 Console 官网口径完全一致）
            if let meters = goMeters {
                sep()
                let mq = dominantModelQuota()

                // 标题：主用模型 + 官方月限（换算细节放说明行，避免截断）
                let title: String
                if let mq {
                    title = "Go 额度 · \(mq.id)（月限 \(fmtUSD(mq.monthLimit))）"
                } else {
                    title = "Go 额度（allowance 计量，Console 同口径）"
                }
                infoItem(NSAttributedString(string: title, attributes: [
                    .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                ]))

                let quotaList: [(String, GoMeter?)] = [
                    ("5 小时窗口", meters.fiveHour),
                    ("每周额度", meters.week),
                    ("每月额度", meters.month),
                ]
                var has = false
                var listEquivs: [String] = []      // 列表价等价金额（5h/周/月）
                for (label, meter) in quotaList {
                    guard let meter,
                          let usedCents = Double(meter.usedMicroCents ?? "") else { continue }
                    let usedUSD = usedCents / 1e8
                    let limitUSD = (Double(meter.limitMicroCents ?? "") ?? 0) / 1e8
                    guard limitUSD > 0 else { continue }
                    has = true
                    let fraction = usedUSD / limitUSD
                    let color: NSColor = fraction >= 0.85 ? cRed : (fraction >= 0.6 ? cOrange : cBlue)
                    var resetText = ""
                    if let resetsAt = parseISO(meter.resetsAt) {
                        resetText = "\(fmtDuration(resetsAt.timeIntervalSinceNow))后重置"
                    }
                    if let mq {
                        listEquivs.append(fmtUSD(usedUSD / (mq.monthLimit / 60.0)))
                    }
                    let item = NSMenuItem()
                    item.view = QuotaRowView(
                        label: label,
                        pctText: String(format: "已用 %.0f%%", fraction * 100),
                        amountText: "\(fmtUSD(usedUSD)) / \(fmtUSD(limitUSD))",
                        resetText: resetText,
                        fraction: CGFloat(min(fraction, 1)),
                        color: color
                    )
                    self.menu.addItem(item)
                }
                if has {
                    // 说明拆成两行，都保持短句，避免 340px 宽度下被截断
                    coloredText([("allowance 计量（与官网一致）", NSColor.secondaryLabelColor)], indent: 1)
                    var note: String
                    if let mq, listEquivs.count == 3 {
                        note = "≈ 列表价 \(listEquivs.joined(separator: " / "))（月限 \(fmtUSD(mq.monthLimit))）"
                    } else if mq != nil {
                        note = "部分窗口暂无数据，列表价等价略"
                    } else {
                        note = "多模型混合使用，不便换算列表价"
                    }
                    coloredText([(note, NSColor.secondaryLabelColor)], indent: 1)
                    if let start = parseISO(goStatus?.access?.startsAt),
                       let end = parseISO(goStatus?.access?.endsAt) {
                        let f = DateFormatter(); f.dateFormat = "MM-dd"
                        coloredText([("计费周期 \(f.string(from: start)) → \(f.string(from: end))", NSColor.secondaryLabelColor)], indent: 1)
                    }
                }
            }

            // 5) 模型明细（每档一个子菜单）
            sep()
            let modelParent = NSMenuItem(title: "模型明细", action: nil, keyEquivalent: "")
            let modelSub = makeMenu()
            modelParent.submenu = modelSub
            self.menu.addItem(modelParent)
            for (range, label) in [("24h", "今日（0 点起）"), ("7d", "近 7 天（含今日）"), ("30d", "近 30 天（含今日）")] {
                let list = modelsByRange[range] ?? []
                guard !list.isEmpty else { continue }
                infoItem(NSAttributedString(string: label, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                ]), into: modelSub)
                let costs = list.map { Double(toInt($0.totalCostMicroCents)) }
                let useCost = (costs.max() ?? 0) > 0
                let values = useCost ? costs : list.map { Double(toInt($0.totalRequests)) }
                let maxV = max(values.max() ?? 1, 1)
                for (i, m) in list.prefix(8).enumerated() {
                    let color = palette[i % palette.count]
                    let item = NSMenuItem()
                    let stats = "\(fmtCount(m.totalRequests))次 · \(fmtCost(m.totalCostMicroCents))"
                    var note = ""
                    if range == "30d", let lim = monthlyLimit(for: m.model ?? "") {
                        note = "月额度 \(fmtUSD(lim))"
                    }
                    item.view = ModelRowView(
                        name: m.model ?? "?",
                        stats: stats,
                        note: note,
                        fraction: CGFloat(values[i] / maxV),
                        color: color
                    )
                    modelSub.addItem(item)
                }
                modelSub.addItem(.separator())
            }

            // 6) 最近请求
            if !logs.isEmpty {
                let logParent = NSMenuItem(title: "最近请求（\(min(logs.count, 15)) 条）", action: nil, keyEquivalent: "")
                let logSub = makeMenu()
                logParent.submenu = logSub
                self.menu.addItem(logParent)
                let tf = DateFormatter()
                tf.dateFormat = "MM-dd HH:mm:ss"
                for log in logs.prefix(15) {
                    let failed = (log.outcome ?? "") != "succeeded"
                    let when = log.startedAt.map { tf.string(from: Date(timeIntervalSince1970: Double($0) / 1000)) } ?? "--"
                    let tok = "\(fmtTokens(log.inputTokens ?? 0))→\(fmtTokens(log.outputTokens ?? 0))"
                    let dur = String(format: "%.1fs", Double(log.durationMs ?? 0) / 1000)
                    let parts = NSMutableAttributedString()
                    func add(_ s: String, _ c: NSColor) {
                        parts.append(NSAttributedString(string: s, attributes: [
                            .font: NSFont.menuFont(ofSize: 12), .foregroundColor: c,
                        ]))
                    }
                    add(failed ? "✕ " : "", cRed)
                    add(when + "  ", .labelColor)
                    add(log.model ?? "?", failed ? cRed : .labelColor)
                    add("  " + tok + " · " + dur + " · ", .labelColor)
                    add(fmtUSD(log.cost ?? 0), cGreen)
                    infoItem(parts, into: logSub)
                }
            }

            // 7) 请求质量统计
            if !logs.isEmpty {
                let n = Double(logs.count)
                let ok = logs.filter { ($0.outcome ?? "") == "succeeded" }.count
                let ttfts = logs.compactMap { $0.timeToFirstTokenMs }.map { Double($0) }
                let durs = logs.compactMap { $0.durationMs }.map { Double($0) }
                let avgTTFT = ttfts.isEmpty ? 0 : ttfts.reduce(0, +) / Double(ttfts.count)
                let avgDur = durs.isEmpty ? 0 : durs.reduce(0, +) / Double(durs.count)
                let outTok = logs.reduce(Int64(0)) { $0 + ($1.outputTokens ?? 0) }
                let reasoning = logs.reduce(Int64(0)) { $0 + ($1.reasoningTokens ?? 0) }
                let sessions = Set(logs.compactMap { $0.sessionID })
                let avgAttempts = logs.reduce(0) { $0 + ($1.attemptCount ?? 1) }
                sep()
                infoItem(NSAttributedString(string: "请求质量（最近 \(logs.count) 次）", attributes: [
                    .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                ]))
                let successRate = Double(ok) / max(n, 1)
                coloredText([
                    ("成功率 ", .labelColor),
                    (String(format: "%.1f%%", successRate * 100), successRate >= 0.99 ? cGreen : cOrange),
                    ("  ·  ", .secondaryLabelColor),
                    ("失败 \(logs.count - ok) 次", logs.count - ok > 0 ? cRed : .secondaryLabelColor),
                ], indent: 1)
                coloredText([
                    ("首字延迟 ", .labelColor), (String(format: "%.1fs", avgTTFT / 1000), cBlue),
                    ("  ·  总耗时 ", .labelColor), (String(format: "%.1fs", avgDur / 1000), cBlue),
                ], indent: 1)
                coloredText([
                    ("思考 token 占比 ", .labelColor),
                    (outTok > 0 ? String(format: "%.0f%%", Double(reasoning) / Double(outTok) * 100) : "—", cPurple),
                    ("  ·  会话 \(sessions.count) 个", .secondaryLabelColor),
                ], indent: 1)
                coloredText([
                    ("平均重试 ", .labelColor), (String(format: "%.2f", Double(avgAttempts) / max(n, 1)), .labelColor),
                    (" 次/请求", .secondaryLabelColor),
                ], indent: 1)
            }

            // 8) 订阅信息
            if let st = goStatus {
                sep()
                let parent = NSMenuItem(title: "订阅信息", action: nil, keyEquivalent: "")
                let sub = makeMenu()
                parent.submenu = sub
                self.menu.addItem(parent)
                if let product = st.product {
                    coloredText([("产品 ", .labelColor), (product.uppercased(), cBlue)], into: sub)
                }
                if let kind = st.paymentMethodKind {
                    coloredText([("支付方式 ", .labelColor), (kind, .labelColor)], into: sub)
                }
                if let end = parseISO(st.access?.endsAt) {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
                    coloredText([("本周期结束 ", .labelColor), (f.string(from: end), .labelColor)], into: sub)
                }
                if let up = st.upgradePrice, let amt = up.amountMicroCents {
                    coloredText([("升级价格 ", .labelColor), (fmtUSD(Double(toInt(amt)) / 1e8) + "/月", cGreen)], into: sub)
                }
                if let cancel = st.cancelAtPeriodEnd {
                    coloredText([("自动续费 ", .labelColor), (cancel ? "本期结束后取消" : "开启", cancel ? cOrange : cGreen)], into: sub)
                }
            }

            // 9) 底部操作
            sep()
            if let updated = lastUpdated {
                let f = DateFormatter()
                f.dateFormat = "HH:mm:ss"
                coloredText([("更新于 \(f.string(from: updated))", NSColor.secondaryLabelColor)])
            }
            addAction("立即刷新", action: #selector(refresh), key: "r")

            // 连接设置（接口地址 / API Key 可随时改，无需重编译）
            let connSub = makeMenu()
            let connParent = NSMenuItem(title: "连接设置", action: nil, keyEquivalent: "")
            connParent.submenu = connSub
            self.menu.addItem(connParent)
            coloredText([("接口地址 ", .labelColor), (apiBase, cBlue)], into: connSub)
            coloredText([("API Key ", .labelColor), (maskedKey, .labelColor)], into: connSub)
            coloredText([("刷新间隔 ", .labelColor),
                         ("\(max(60, config?.refreshIntervalSeconds ?? 300) / 60) 分钟", .labelColor)], into: connSub)
            connSub.addItem(.separator())
            let editItem = NSMenuItem(title: "修改接口地址 / API Key…", action: #selector(showSettings), keyEquivalent: ",")
            editItem.target = self
            connSub.addItem(editItem)
            let testItem = NSMenuItem(title: "测试连接", action: #selector(testConnection), keyEquivalent: "")
            testItem.target = self
            connSub.addItem(testItem)
            let resetItem = NSMenuItem(title: "接口地址恢复默认", action: #selector(resetAPIBase), keyEquivalent: "")
            resetItem.target = self
            connSub.addItem(resetItem)
            let revealItem = NSMenuItem(title: "打开配置文件位置", action: #selector(revealConfigFile), keyEquivalent: "")
            revealItem.target = self
            connSub.addItem(revealItem)

            addAction("打开 Console 网页", action: #selector(openConsole), key: "o")
            addAction("开机自启动", action: #selector(toggleLaunchAtLogin), key: "",
                      state: launchAgentExists() ? .on : .off)
            sep()
            addAction("退出", action: #selector(NSApplication.terminate(_:)), key: "q")
        }
    }

    // MARK: 动作

    @objc private func openConsole() {
        if let url = URL(string: consoleURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 连接设置

    private func showInfo(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "好")
        a.runModal()
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        let rowH: CGFloat = 32
        let width: CGFloat = 470
        let height = rowH * 4
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        func makeRow(_ label: String, _ value: String, _ y: CGFloat, placeholder: String = "") -> NSTextField {
            let l = NSTextField(labelWithString: label)
            l.font = .systemFont(ofSize: 12)
            l.textColor = .labelColor
            l.alignment = .right
            l.lineBreakMode = .byTruncatingTail
            l.frame = NSRect(x: 0, y: y + 4, width: 92, height: 18)
            container.addSubview(l)

            let tf = NSTextField(frame: NSRect(x: 100, y: y, width: width - 100, height: 24))
            tf.stringValue = value
            tf.placeholderString = placeholder
            tf.font = .systemFont(ofSize: 12)
            tf.isBezeled = true
            tf.bezelStyle = .roundedBezel
            tf.isEditable = true
            tf.isSelectable = true
            container.addSubview(tf)
            return tf
        }

        let keyField = makeRow("API Key", config?.apiKey ?? "", rowH * 3, placeholder: "oc_sk_…")
        let baseField = makeRow("接口地址", apiBase, rowH * 2, placeholder: Monitor.defaultAPIBase)
        let consoleField = makeRow("网页地址", config?.consoleURL ?? Monitor.defaultConsoleURL, rowH * 1)
        let intervalField = makeRow("刷新间隔(秒)", "\(max(60, config?.refreshIntervalSeconds ?? 300))", 0)

        let alert = NSAlert()
        alert.messageText = "连接设置"
        alert.informativeText = "接口地址变了、或者换了 API Key，在这里改就行，保存后立即生效，不需要重新编译。"
        alert.accessoryView = container
        alert.addButton(withTitle: "保存并刷新")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = baseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let console = consoleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let intervalText = intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if base.isEmpty { base = Monitor.defaultAPIBase }
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        guard base.hasPrefix("http://") || base.hasPrefix("https://"), URL(string: base) != nil else {
            showInfo("接口地址无效", "需要以 http:// 或 https:// 开头，例如：\n\(Monitor.defaultAPIBase)")
            return
        }
        if key.isEmpty {
            showInfo("API Key 为空", "仍会保存，但在填入 Key 之前拉不到数据。")
        }

        var interval = Int(intervalText) ?? 300
        interval = min(max(interval, 60), 86400)

        let cfg = Config(apiKey: key,
                         refreshIntervalSeconds: interval,
                         consoleURL: console.isEmpty ? Monitor.defaultConsoleURL : console,
                         apiBaseURL: base)
        guard saveConfigToDisk(cfg) else {
            showInfo("保存失败", lastError ?? "无法写入配置文件")
            return
        }
        config = cfg
        lastError = key.isEmpty ? "请先在「连接设置…」填入 API Key" : nil
        scheduleTimer()
        refresh()
    }

    @objc private func testConnection() {
        let key = (config?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            showInfo("无法测试", "还没有设置 API Key，请先在「修改接口地址 / API Key…」里填入。")
            return
        }
        let base = apiBase
        guard let url = URL(string: "\(base)/usage/summary?range=24h") else {
            showInfo("接口地址无效", "\(base) 不是合法 URL。")
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")

        var status: Int?
        var body = Data()
        var errText: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            status = (resp as? HTTPURLResponse)?.statusCode
            body = data ?? Data()
            errText = err?.localizedDescription
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 18)

        if let errText {
            showInfo("连接失败", "地址：\(base)\n\n错误：\(errText)\n\n"
                     + "若提示域名解析失败 / 找不到主机，说明接口地址已变更，请修改「接口地址」。")
            return
        }
        guard let status else {
            showInfo("连接超时", "18 秒内无响应：\(base)")
            return
        }
        if (200..<300).contains(status) {
            var detail = "HTTP \(status)，接口正常。"
            if let s = try? JSONDecoder().decode(SummaryResp.self, from: body) {
                detail += "\n24h：\(fmtCount(s.totalRequests)) 次 · \(fmtCost(s.totalCostMicroCents))"
            }
            showInfo("连接成功", "地址：\(base)\n\(detail)\nKey：\(maskedKey)")
        } else if status == 401 {
            showInfo("Key 无效", "HTTP 401 —— 接口地址是通的，但 API Key 无效或已被撤销。\n\n"
                     + "请到 Console 重新复制 Key 后填入。")
        } else if status == 404 {
            showInfo("路径不存在", "HTTP 404 —— 主机可达，但 \(base) 下没有这些接口。\n\n"
                     + "接口可能已迁移，请修改「接口地址」（例如换成新的 API 前缀）。")
        } else {
            showInfo("接口异常", "HTTP \(status)\n地址：\(base)")
        }
    }

    @objc private func resetAPIBase() {
        var cfg = config ?? Config(apiKey: "", refreshIntervalSeconds: 300,
                                   consoleURL: Monitor.defaultConsoleURL,
                                   apiBaseURL: Monitor.defaultAPIBase)
        cfg.apiBaseURL = Monitor.defaultAPIBase
        guard saveConfigToDisk(cfg) else { return }
        config = cfg
        lastError = nil
        refresh()
        rebuildMenu()
    }

    @objc private func revealConfigFile() {
        let path = configPath()
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            showInfo("配置文件不存在", path)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAgentExists() {
            removeLaunchAgent()
        } else {
            installLaunchAgent()
        }
        rebuildMenu()
    }

    // MARK: LaunchAgent

    private func launchAgentExists() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private func installLaunchAgent() {
        let dir = (launchAgentPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let bundlePath = Bundle.main.bundlePath
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array><string>open</string><string>\(bundlePath)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
        </dict>
        </plist>
        """
        do {
            try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } catch {
            lastError = "写入 LaunchAgent 失败：\(error.localizedDescription)"
            return
        }
        runLaunchctl(["unload", launchAgentPath])
        runLaunchctl(["load", launchAgentPath])
    }

    private func removeLaunchAgent() {
        runLaunchctl(["unload", launchAgentPath])
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    private func runLaunchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = Monitor()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
