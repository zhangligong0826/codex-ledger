import AppKit
import SwiftUI
import CoreImage
import UniformTypeIdentifiers

@MainActor enum ShareImages {
    static func qr() -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(ShareSnapshot.downloadURL.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let result = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(result, from: result.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    static func capture(_ view: NSView) -> NSImage? {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size); image.addRepresentation(rep); return image
    }
    static func card(_ value: ShareSnapshot, title: String, showName: Bool, language: String, dark: Bool) -> NSImage? {
        let publicTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let visibleTitle = publicTitle.isEmpty ? (showName ? value.privateTitle : (language == "en" ? LedgerText.english[value.kind] ?? value.kind : value.kind)) : publicTitle
        let view = ShareCardView(value: value, title: visibleTitle, language: language)
            .environment(\.colorScheme, dark ? .dark : .light).frame(width: 360, height: 480)
        let renderer = ImageRenderer(content: view)
        var result: NSImage?
        // An explicit bitmap context avoids a Metal-backed offscreen target.
        renderer.render(rasterizationScale: 3) { size, draw in
            guard let context = CGContext(data: nil, width: Int(size.width * 3), height: Int(size.height * 3),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: 3, y: 3)
            draw(context)
            if let image = context.makeImage() { result = NSImage(cgImage: image, size: size) }
        }
        return result
    }
    static func png(_ image: NSImage) -> Data? {
        guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor struct ShareCardView: View {
    let value: ShareSnapshot
    let title: String
    let language: String
    private func T(_ key: String) -> String { language == "en" ? LedgerText.english[key] ?? key : key }
    private var peak: Int64 { value.days.map { $0.usage.total }.max() ?? 0 }
    private var offset: Int {
        var calendar = Calendar.current; calendar.timeZone = TimeZone(identifier: value.timezone) ?? .current
        return value.days.first.map { (calendar.component(.weekday, from: $0.date) + 6) % 7 } ?? 0
    }
    private func money(_ cost: CostEstimate) -> String {
        cost.hasEstimate ? LedgerPricing.money(cost.totalUSD) + (cost.unpricedTokens > 0 ? " *" : "") : T("单价未知")
    }
    private var columns: Int { (offset + value.days.count + 6) / 7 }
    private let greens = [Color.primary.opacity(0.07), Color(red: 0.61, green: 0.82, blue: 0.66), Color(red: 0.29, green: 0.66, blue: 0.43), Color(red: 0.15, green: 0.49, blue: 0.31), Color(red: 0.07, green: 0.34, blue: 0.23)]
    private var note: String {
        var parts = [T("API 成本估算，非实际账单"), value.priceDate]
        if value.warning { parts.append(T("部分日志不可读")) }
        if value.cost.unpricedTokens > 0 || value.monthlyCost.unpricedTokens > 0 { parts.append(T("含未计价用量")) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            brand.frame(width: 316, height: 16, alignment: .topLeading).offset(x: 22, y: 22)
            Text(title).font(.system(size: 23, weight: .bold)).lineLimit(2)
                .frame(width: 316, height: 57, alignment: .topLeading).offset(x: 22, y: 48)
            amount.frame(width: 316, height: 110, alignment: .topLeading).offset(x: 22, y: 112)
            if let cost = value.completionCost {
                HStack { Text(T("完成时")); Spacer(); Text(money(cost) + " USD").bold().lineLimit(1).minimumScaleFactor(0.3) }
                    .font(.system(size: 10)).frame(width: 316, height: 14).offset(x: 22, y: 221)
            }
            heatmap.offset(x: 22, y: value.completionCost == nil ? 232 : 250)
            footer.frame(width: 316, height: 59, alignment: .topLeading).offset(x: 22, y: 397)
            Text(note).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(2)
                .frame(width: 316, height: 18, alignment: .topLeading).offset(x: 22, y: 460)
        }.frame(width: 360, height: 480, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor))
    }
    private var brand: some View {
        HStack {
            Label("Codex Ledger", systemImage: "chart.bar.fill").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("LOCAL").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
    }
    private var amount: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(T("预估 API 花费") + " · USD").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(money(value.cost)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
            Text(value.range + (value.filtered ? " · " + T("已筛选") : "")).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(compactTokens(value.usage.total) + " tokens")
                Text(String(value.turns) + " " + T("任务轮次"))
                Text(String(value.models) + " " + T("模型"))
            }.font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
    }
    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(T("近 30 天")).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(String(value.activeDays) + "/30 " + T("活跃天数")).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(0..<columns, id: \.self) { column in activityColumn(column) }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(money(value.monthlyCost)).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.35)
                    Text("USD").font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(compactTokens(value.monthlyUsage.total) + " tokens").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            if let first = value.days.first, let last = value.days.last {
                Text(dayLabel(first.date) + " — " + dayLabel(last.date) + " · " + value.timezone).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(10).frame(width: 316, height: 136, alignment: .topLeading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func activityColumn(_ column: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<7) { row in
                RoundedRectangle(cornerRadius: 2).fill(cellColor(column * 7 + row - offset)).frame(width: 10, height: 10)
            }
        }
    }
    private func cellColor(_ index: Int) -> Color {
        guard value.days.indices.contains(index) else { return .clear }
        return greens[value.days[index].intensity(peak: peak)]
    }
    private var footer: some View {
        HStack(spacing: 10) {
            if let qr = ShareImages.qr() {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 49, height: 49).padding(5).background(.white).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(T("扫码下载 · Mac / Windows")).font(.system(size: 10, weight: .semibold))
                Text("zhangligong0826.github.io/codex-ledger").font(.system(size: 7)).lineLimit(1)
                Text(T("本地统计 · MIT 开源")).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "MM/dd"
        formatter.timeZone = TimeZone(identifier: value.timezone) ?? .current; return formatter.string(from: date)
    }
}

@MainActor struct SharePreviewView: View {
    let preview: SharePreview
    let language: String
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var showName = false
    @State private var dark = false
    @State private var status = ""
    private var image: NSImage? {
        preview.screenshot ?? preview.snapshot.flatMap { ShareImages.card($0, title: title, showName: showName, language: language, dark: dark) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(L(preview.screenshot == nil ? "分享卡片" : "当前界面截图")).font(.headline); Spacer(); Button(L("关闭")) { close() } }
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 370, maxHeight: 420).background(Color.primary.opacity(0.04)) }
            else { Text(L("图片生成失败")) }
            if preview.snapshot != nil {
                TextField(L("公开标题（可选）"), text: $title).onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
                HStack { Toggle(L("显示原始名称"), isOn: $showName); Spacer(); Toggle(L("深色卡片"), isOn: $dark) }
                Text(L("默认隐藏名称、路径和对话标题。请确认预览后分享。")).font(.caption).foregroundStyle(.secondary)
            } else { Text(L("截图包含当前可见的名称和标题，请确认预览后分享。")).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text(status).font(.caption).foregroundStyle(.secondary); Spacer()
                Button(L("复制图片")) { copy() }.disabled(image == nil)
                Button(L("保存 PNG…")) { save() }.disabled(image == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 430).onAppear { dark = colorScheme == .dark }
    }
    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        status = NSPasteboard.general.writeObjects([image]) ? L("已复制") : L("复制失败，请重试")
    }
    private func save() {
        guard let image, let data = ShareImages.png(image) else { status = L("图片生成失败"); return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Codex-Ledger-Share.png"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); status = L("已保存") }
            catch { status = L("保存失败，请重试") }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

@MainActor struct LedgerShareMenu: View {
    @ObservedObject var store: LedgerStore
    let overview: Bool
    var body: some View {
        Menu {
            Button(L("生成分享卡片")) { store.makeShareCard(overview: overview) }
            Button(L("保存当前界面")) { store.captureInterface?(overview) }
            Divider()
            Button(L("导出 CSV")) { store.exportCSV(models: overview ? false : nil) }
        } label: { Image(systemName: "square.and.arrow.up") }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(store.busy || store.isSharing || !store.rangeReady || !store.activityReady || store.dataUnavailable || (!overview && store.requiresGoalBook && !store.goalBookAvailable))
        .help(L(store.busy || !store.rangeReady ? "正在整理日志，请稍候" : !overview && store.requiresGoalBook && !store.goalBookAvailable ? "目标账本无法读取，原有数据已保留。" : store.dataUnavailable ? "需要检查数据目录" : "分享"))

    }
}
