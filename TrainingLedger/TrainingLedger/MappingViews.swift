import SwiftUI
import TrainingCore

struct MappingPage: View {
  @Environment(TrainingStore.self) private var store
  @State private var search = ""
  @State private var editing: Person?
  private var people: [Person] { store.people.filter { $0.matches(search) } }
  var body: some View {
    List {
      Section {
        Text("真名由你填写。每个平台的 ID 独立保存，改真名或昵称不会改变绑定，也不会清除训练记录。").font(.footnote).foregroundStyle(
          Theme.secondaryText)
      }
      ForEach(people) { person in
        Section {
          Button {
            editing = person
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName).font(.headline).foregroundStyle(.primary)
                Text(
                  person.realName.isEmpty ? "真名未填写" : person.alias.map { "训练昵称 · " + $0 } ?? "已填写真名"
                ).font(.caption).foregroundStyle(Theme.secondaryText)
              }
              Spacer()
              Text("编辑").font(.subheadline)
            }
          }
          ForEach(person.accounts) { account in
            AccountMappingRow(account: account, person: person)
              .contextMenu {
                Button("复制平台 ID", systemImage: "doc.on.doc") {
                  UIPasteboard.general.string = account.handle
                }
              }
          }
          if person.accounts.isEmpty {
            Text("尚未绑定平台账号").font(.caption).foregroundStyle(Theme.secondaryText)
          }
        }
      }
      if people.isEmpty { EmptyTraining(title: "没有匹配的映射", detail: "可以搜索真名、昵称或平台 ID。") }
    }.navigationTitle("人物与账号映射").navigationBarTitleDisplayMode(.inline).searchable(
      text: $search, prompt: "真名、昵称或平台 ID"
    )
    .sheet(item: $editing) { PersonEditor(person: $0) }
  }
}
private struct AccountMappingRow: View {
  let account: OJAccount
  let person: Person
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          OJBadge(oj: account.oj)
          identity
          Label(person.displayName, systemImage: "person.fill")
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          OJBadge(oj: account.oj)
          identity.layoutPriority(1)
          Spacer(minLength: 5)
          Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.secondaryText)
          Text(person.displayName).font(.caption.weight(.medium))
            .multilineTextAlignment(.trailing)
        }
      }
    }.padding(.vertical, 5)
  }
  private var identity: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(account.handle).font(.subheadline.monospaced()).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if !account.platformName.isEmpty, account.platformName != account.handle {
        Text("平台昵称 · " + account.platformName).font(.caption)
          .foregroundStyle(Theme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
struct SourcesPage: View {
  @Environment(TrainingStore.self) private var store
  var body: some View {
    List {
      ForEach(store.people) { person in
        Section(person.displayName) {
          ForEach(person.accounts) { account in AccountStatus(account: account) }
        }
      }
      if store.accounts.isEmpty { EmptyTraining(title: "尚未绑定账号", detail: "先添加人物和平台 ID。") }
    }.navigationTitle("来源状态").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncButton() } }
  }
}
