import SpendingCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// `Category` alone clashes with the Objective-C runtime type of the same name.
typealias Cat = SpendingCore.Category

enum Fmt {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "el_GR")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        return f
    }()

    static func money(_ cents: Int) -> String {
        currency.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents)"
    }
}

extension Color {
    static let brand = Color(red: 0.06, green: 0.62, blue: 0.45)

    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0x64748b
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Color.brand }
}

func levelColor(_ ratio: Double) -> Color {
    ratio >= 1 ? .red : ratio >= 0.8 ? .orange : .green
}

func ratio(_ spent: Int, _ budget: Int) -> Double {
    budget > 0 ? Double(spent) / Double(budget) : (spent > 0 ? 1 : 0)
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = .brand
    var track: Color = Color(.tertiarySystemFill)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

struct CategoryIcon: View {
    let category: Cat
    var size: CGFloat = 38

    var body: some View {
        Text(category.emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Color(hex: category.color).opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct PurchaseRow: View {
    let purchase: Purchase
    let category: Cat

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(purchase.store.isEmpty ? (purchase.items.first?.name ?? "Αγορά") : purchase.store)
                        .font(.body.weight(.semibold)).lineLimit(1)
                    if purchase.source == "applepay" {
                        Image(systemName: "apple.logo").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(purchase.total)).font(.body.weight(.semibold)).monospacedDigit()
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let names = purchase.items.map(\.name).joined(separator: ", ")
        return purchase.items.count > 1 ? "\(purchase.items.count) προϊόντα · \(names)" : names
    }

    private var meta: String {
        let maxDays = purchase.items.map(\.days).max() ?? 1
        return (purchase.unexpected ? "⚡ " : "") + Days.label(purchase.date) + (maxDays > 1 ? " · ÷\(maxDays) ημ." : "")
    }
}

struct CategoryBar: View {
    let category: Cat
    let cents: Int
    let max: Int
    var percent: Int?
    var budget: Int?
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(category.emoji) \(category.name)").lineLimit(1)
                Spacer()
                Text(Fmt.money(cents)).fontWeight(.semibold).monospacedDigit()
                if let b = budget { Text("/ \(Fmt.money(b))").foregroundStyle(.secondary).monospacedDigit() }
                if let p = percent { Text("\(p)%").foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.subheadline)
            ProgressBar(value: Double(cents) / Double(Swift.max(max, 1)), color: Color(hex: category.color))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, selected ? 8 : 0)
        .background(selected ? Color(.tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

struct AddButton: View {
    @Environment(Router.self) private var router
    var body: some View {
        Button {
            router.newPurchase()
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
        .accessibilityLabel("Νέα αγορά")
    }
}

/// A .json file for the share sheet / Files app.
struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
