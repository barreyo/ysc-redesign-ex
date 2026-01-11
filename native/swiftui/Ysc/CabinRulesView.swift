//
//  CabinRulesView.swift
//  Ysc
//
//  Split-view sidebar component for displaying Tahoe cabin rules

import SwiftUI
import LiveViewNative

// Data models
struct RuleCategory: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct RuleItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String

    // Custom decoding to generate ID if not present in JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        // Generate ID since it's not in the JSON
        id = UUID()
    }

    enum CodingKeys: String, CodingKey {
        case title
        case content
    }
}

struct RulesData: Codable {
    let categories: [RuleCategory]
    let rules: [String: [RuleItem]]
}

@LiveElement
struct CabinRules<Root: RootRegistry>: View {
    let element: ElementNode
    @Event("select_category", type: "click") private var selectCategory

    @State private var selectedCategory: String?

    // Parse data from element attributes
    private var rulesData: RulesData? {
        let dataAttr = element.attributeValue(for: "data")

        guard let dataString = dataAttr as? String else {
            return nil
        }

        // Decode HTML entities
        let decodedString = dataString
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        guard let data = decodedString.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(RulesData.self, from: data)
        } catch {
            print("[CabinRules] JSON decode error: \(error)")
            return nil
        }
    }

    var body: some View {
        if let data = rulesData {
            splitView(data: data)
        } else {
            VStack(spacing: 12) {
                Text("Loading rules...")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func splitView(data: RulesData) -> some View {
        let categoryId = selectedCategory ?? data.categories.first?.id ?? ""
        HStack(alignment: .top, spacing: 0) {
            sidebarView(data: data)
            Divider()
            contentView(data: data, categoryId: categoryId)
        }
        .onAppear {
            updateSelectedCategory(from: data)
        }
        .onChange(of: element.attributeValue(for: "selectedCategory")) { _ in
            updateSelectedCategory(from: data)
        }
    }
    
    @ViewBuilder
    private func sidebarView(data: RulesData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cabin Rules")
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(data.categories) { category in
                        categoryButton(category: category)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    @ViewBuilder
    private func categoryButton(category: RuleCategory) -> some View {
        let isSelected = selectedCategory == category.id
        Button(action: {
            selectedCategory = category.id
            selectCategory(value: ["category": category.id])
        }) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 24)

                Text(category.title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func contentView(data: RulesData, categoryId: String) -> some View {
        if let rules = data.rules[categoryId] {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    categoryHeader(data: data, categoryId: categoryId)
                    rulesList(rules: rules)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Text("Select a category")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func categoryHeader(data: RulesData, categoryId: String) -> some View {
        if let category = data.categories.first(where: { $0.id == categoryId }) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.blue)

                Text(category.title)
                    .font(.system(size: 36, weight: .bold))
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private func rulesList(rules: [RuleItem]) -> some View {
        ForEach(rules) { rule in
            VStack(alignment: .leading, spacing: 12) {
                Text(rule.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)

                Text(rule.content)
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func updateSelectedCategory(from data: RulesData) {
        if let categoryId = element.attributeValue(for: "selectedCategory") as? String {
            selectedCategory = categoryId
        } else if selectedCategory == nil, let firstCategory = data.categories.first {
            selectedCategory = firstCategory.id
        }
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct CabinRulesView<Root: RootRegistry> {
        enum TagName: String {
            case cabinRules = "CabinRulesView"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .cabinRules:
                CabinRules<Root>(element: element)
            }
        }
    }
}
