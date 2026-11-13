import SwiftUI
import PocketCore
import UniformTypeIdentifiers

struct TrainingPlanEntry: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  var body: some View {
    NavigationLink { TrainingPlanScreen(model: model, engine: engine) } label: {
      if let plan = model.plans.plan { PlanOverviewFace(plan: plan, entry: true) }
      else { PocketDestinationLabel(title: "我的训练题单", detail: "导入 Obsidian 题单，接着已有进度刷题", symbol: "checklist").pocketSurface() }
    }.buttonStyle(.plain).accessibilityIdentifier("training-plan-entry")
  }
}
struct PlanOverviewFace: View {
  let plan: TrainingPlan
  var entry = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Label("我的主线训练", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(PocketStyle.heroAccent)
        Spacer()
        if entry { Image(systemName: "arrow.up.right").foregroundStyle(PocketStyle.heroAccent).accessibilityHidden(true) }
      }
      Text(plan.title).font(.title2.bold()).foregroundStyle(.white)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(String(plan.completed)).font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(PocketStyle.heroAccent)
        Text("/ \(plan.total) AC").font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.8))
        Spacer()
        Text(plan.fraction, format: .percent.precision(.fractionLength(0))).font(.headline.monospacedDigit()).foregroundStyle(.white)
      }.accessibilityElement(children: .ignore).accessibilityLabel("总进度，\(plan.completed) / \(plan.total) 道 AC")
      ProgressView(value: plan.fraction).tint(PocketStyle.heroAccent).accessibilityHidden(true)
      HStack {
        Text("\(plan.completedGroups) / \(plan.groups.count) 组完成")
        Spacer()
        if let group = plan.currentGroup { Text("当前 \(group.id) 组 · \(group.completed)/\(group.problems.count)") }
        else { Label("全部完成", systemImage: "checkmark.circle") }
      }.font(.caption).foregroundStyle(.white.opacity(0.8))
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(PocketStyle.hero, in: RoundedRectangle(cornerRadius: 26))
  }
}
struct TrainingPlanScreen: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  @State private var importing = false
  @State private var choosingFolder = true
  @State private var exporting = false
  @State private var exportDocument = PocketJSONDocument(data: Data())
  @State private var query = ""
  @ScaledMetric(relativeTo: .body) private var groupWidth = 72.0
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let plan = model.plans.plan {
          if query.isEmpty {
            PlanOverviewFace(plan: plan)
            syncSection(plan)
            currentSection(plan)
            NavigationLink { PlanProblemsScreen(model: model, engine: engine, favoritesOnly: true) } label: {
              PocketDestinationLabel(title: "好题收藏夹", detail: "\(plan.favorites) 道 · 收藏不计入 AC 进度", symbol: "star", color: PocketStyle.amber).pocketSurface()
            }.buttonStyle(.plain)
            PocketSectionTitle(title: "A–Z 进度", subtitle: "按自己的节奏刷，不用为了跳组勾掉未做的题")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: groupWidth), spacing: 10)], spacing: 10) {
              ForEach(plan.groups) { group in
                NavigationLink { PlanProblemsScreen(model: model, engine: engine, groupID: group.id) } label: {
                  PlanGroupTile(group: group, current: plan.currentGroup?.id == group.id)
                }.buttonStyle(.plain).accessibilityIdentifier("plan-group-\(group.id)")
              }
            }
            NavigationLink { PlanProblemsScreen(model: model, engine: engine) } label: {
              PocketDestinationLabel(title: "全部题目", detail: "\(plan.total - plan.completed) 道未 AC · \(plan.total) 道题", symbol: "list.bullet").pocketSurface()
            }.buttonStyle(.plain)
            Text("只按 AC 计算进度，收藏独立。勾选后自动写回，回到 App 时检查更新，也可下拉刷新。iCloud 跨设备传递由系统完成。").font(.footnote).foregroundStyle(.secondary)
          } else {
            let matches = plan.groups.flatMap(\.problems).filter { "\($0.id) \($0.title)".localizedCaseInsensitiveContains(query) }
            if matches.isEmpty { ContentUnavailableView.search(text: query) }
            else { ForEach(matches) { item in PlanProblemRow(item: item, model: model, engine: engine) } }
          }
        } else {
          ContentUnavailableView {
            Label("把正在刷的题单带进来", systemImage: "checklist")
          } description: { Text("选择包含“训练总览.md”和 cf/A.md～Z.md 的文件夹，或导入之前导出的题单 JSON。") }
          Button("关联 Obsidian 题单", systemImage: "folder") { choosingFolder = true; importing = true }.buttonStyle(PocketPrimaryButton()).frame(maxWidth: .infinity)
        }
        if model.plans.busy { ProgressView("正在核对题单…").font(.footnote) }
        if model.plans.plan?.connection == nil, let error = model.plans.error { StatusNotice(title: "题单未更新", message: error, symbol: "exclamationmark.circle") }
        if let notice = model.plans.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
      }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }.background(PocketStyle.canvas).navigationTitle("训练题单").navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "题名或 CF 题号")
      .refreshable { await model.plans.synchronize() }
      .toolbar {
        if model.plans.plan?.connection != nil {
          ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.plans.synchronize() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }.accessibilityLabel("同步题单").disabled(model.plans.busy) }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(model.plans.plan?.connection == nil ? "关联 Obsidian 文件夹" : "重新关联文件夹", systemImage: "folder") { choosingFolder = true; importing = true }
            Button("导入进度备份", systemImage: "square.and.arrow.down") { choosingFolder = false; importing = true }.disabled(model.plans.plan?.connection != nil)
            Button("导出题单与进度", systemImage: "square.and.arrow.up") {
              do { if let plan = model.plans.plan { exportDocument = PocketJSONDocument(data: try plan.encoded()); exporting = true } }
              catch { model.plans.error = error.localizedDescription }
            }.disabled(model.plans.plan == nil)
            if model.plans.plan?.connection != nil { Button("取消关联，保留本机进度", systemImage: "link") { model.plans.change { $0.connection = nil } } }
          } label: { Image(systemName: "ellipsis") }.accessibilityLabel("题单选项").disabled(model.plans.busy)
        }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: choosingFolder ? [.folder] : [.json]) { result in
        switch result { case .success(let url): Task { if choosingFolder { await model.plans.connectFolder(url) } else { await model.plans.importFile(url) } }; case .failure(let error): model.plans.error = error.localizedDescription }
      }
      .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "ICPC训练题单与进度") { result in
        if case .failure(let error) = result { model.plans.error = error.localizedDescription }
      }
  }
  @ViewBuilder private func syncSection(_ plan: TrainingPlan) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let connection = plan.connection {
        Label("已关联 Obsidian", systemImage: "link").font(.subheadline.weight(.semibold)).foregroundStyle(PocketStyle.accent)
        if model.plans.busy { Text("正在合并两边进度…").font(.footnote).foregroundStyle(.secondary) }
        else if let error = model.plans.error {
          Text(error).font(.footnote).foregroundStyle(.secondary)
          Button("重试同步") { Task { await model.plans.synchronize() } }.font(.subheadline.weight(.semibold))
        } else if plan.hasUnsyncedChanges { Text("新勾选已保存在手机，等待写回文件。").font(.footnote).foregroundStyle(.secondary) }
        else if let date = connection.synchronizedAt { Text("本机文件已核对 · \(date.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
        else { Text("首次同步尚未完成。").font(.footnote).foregroundStyle(.secondary) }
      } else {
        Text("与 Obsidian 保持同一份进度").font(.headline).foregroundStyle(PocketStyle.ink)
        Text("首次选择 iCloud 中的“ICPC区域赛训练”整个文件夹，之后 AC 与收藏会双向更新。").font(.footnote).foregroundStyle(.secondary)
        Button("关联 Obsidian 文件夹", systemImage: "folder") { choosingFolder = true; importing = true }.buttonStyle(PocketPrimaryButton()).disabled(model.plans.busy)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).pocketSurface()
  }
  @ViewBuilder private func currentSection(_ plan: TrainingPlan) -> some View {
    HStack {
      PocketSectionTitle(title: "继续训练")
      Picker("当前训练组", selection: Binding<String?>(get: { model.plans.plan?.selectedGroup }, set: { value in model.plans.change { $0.selectedGroup = value } })) {
        Text("自动").tag(String?.none)
        ForEach(plan.groups) { Text("\($0.id) 组").tag(Optional($0.id)) }
      }.pickerStyle(.menu).fixedSize().disabled(model.plans.busy).accessibilityIdentifier("plan-current-group")
    }
    if let group = plan.currentGroup {
      NavigationLink { PlanProblemsScreen(model: model, engine: engine, groupID: group.id) } label: {
        PocketDestinationLabel(title: "\(group.id) 组", detail: group.completed == group.problems.count ? "本组已全部 AC，可以回顾或切换训练组" : "\(group.completed)/\(group.problems.count) AC · 还有 \(group.problems.count - group.completed) 道", symbol: "square.stack").pocketSurface()
      }.buttonStyle(.plain)
      if let next = group.problems.first(where: { !$0.accepted }) {
        NavigationLink { workspace(next) } label: {
          HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(PocketStyle.accent)
            VStack(alignment: .leading, spacing: 5) { Text("下一道未 AC").font(.caption).foregroundStyle(.secondary); Text(next.title).font(.headline).foregroundStyle(PocketStyle.ink); Text("CF \(next.id)").font(.caption).foregroundStyle(.secondary) }
            Spacer()
          }.padding(.horizontal, 4).frame(minHeight: 60)
        }.buttonStyle(.plain)
      }
    } else { Label("这份题单已全部完成", systemImage: "checkmark.seal").foregroundStyle(PocketStyle.accent).padding(.vertical, 12) }
  }
  private func workspace(_ item: PlanProblem) -> some View {
    WorkspaceScreen(model: WorkspaceModel(app: model, problem: PocketProblem(key: item.problem, name: item.title)), engine: engine)
  }
}
struct PlanGroupTile: View {
  let group: PlanGroup
  let current: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 2) { Text(group.id).font(.title3.bold()); Spacer(minLength: 0); if group.completed == group.problems.count { Image(systemName: "checkmark").font(.caption.weight(.bold)) } }
      Text("\(group.completed)/\(group.problems.count)").font(.caption.monospacedDigit())
      ProgressView(value: group.fraction).tint(PocketStyle.accent).accessibilityHidden(true)
    }.foregroundStyle(current ? PocketStyle.accent : PocketStyle.ink).padding(12)
      .background(current ? PocketStyle.wash : PocketStyle.paper, in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(current ? PocketStyle.accent : PocketStyle.line, lineWidth: current ? 1.5 : 0.7) }
      .accessibilityElement(children: .ignore).accessibilityLabel("\(group.id) 组，\(group.completed) / \(group.problems.count) 道 AC\(current ? "，当前训练组" : "")")
  }
}
struct PlanProblemsScreen: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  var groupID: String?
  var favoritesOnly = false
  @State private var filter = "全部"
  @State private var query = ""
  private var items: [PlanProblem] {
    let base = model.plans.plan?.groups.filter { groupID == nil || $0.id == groupID }.flatMap(\.problems) ?? []
    return base.filter { (!favoritesOnly || $0.favorite) && (filter != "未 AC" || !$0.accepted) && (filter != "已 AC" || $0.accepted) && (query.isEmpty || "\($0.id) \($0.title)".localizedCaseInsensitiveContains(query)) }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        if let group = model.plans.plan?.groups.first(where: { $0.id == groupID }) {
          HStack { Text("\(group.completed) / \(group.problems.count) AC").font(.title2.bold()); Spacer(); Text(group.fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(PocketStyle.accent) }
          ProgressView(value: group.fraction).tint(PocketStyle.accent).padding(.bottom, 8)
        }
        Picker("显示题目", selection: $filter) { ForEach(["全部", "未 AC", "已 AC"], id: \.self) { Text($0) } }.pickerStyle(.segmented).padding(.bottom, 8)
        if model.plans.busy { HStack(spacing: 8) { ProgressView(); Text(model.plans.plan?.connection == nil ? "正在保存进度…" : "正在与 Obsidian 合并进度…").font(.footnote).foregroundStyle(.secondary) } }
        if items.isEmpty { ContentUnavailableView("没有符合条件的题目", systemImage: favoritesOnly ? "star" : "checklist", description: Text(favoritesOnly ? "在题目旁点星标即可收藏；收藏与 AC 独立。" : "试试切换筛选或搜索条件。")) }
        ForEach(items) { item in PlanProblemRow(item: item, model: model, engine: engine) }
        if let error = model.plans.error { StatusNotice(title: "保存未完成", message: error, symbol: "exclamationmark.circle") }
        Text("点题名进入题目。AC 手动记录；星标只加入题单收藏，不改变完成进度。").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
      }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }.background(PocketStyle.canvas).navigationTitle(groupID.map { "\($0) 组" } ?? (favoritesOnly ? "好题收藏夹" : "全部题目")).navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "题名或 CF 题号")
      .toolbar {
        if let groupID {
          ToolbarItem(placement: .topBarTrailing) {
            Menu { Button("设为当前训练组") { model.plans.change { $0.selectedGroup = groupID } } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("分组选项").disabled(model.plans.busy)
          }
        }
      }
  }
}
struct PlanProblemRow: View {
  let item: PlanProblem
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink {
        WorkspaceScreen(model: WorkspaceModel(app: model, problem: PocketProblem(key: item.problem, name: item.title)), engine: engine)
      } label: {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.headline).foregroundStyle(PocketStyle.ink).multilineTextAlignment(.leading); Text("CF \(item.id)").font(.caption).foregroundStyle(.secondary) }
          Spacer(minLength: 8); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary).padding(.top, 3)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("plan-open-\(item.id)")
      HStack(spacing: 12) {
        Button { model.plans.toggle(item.id, favorite: false) } label: {
          Label(item.accepted ? "已 AC" : "标记 AC", systemImage: item.accepted ? "checkmark.circle.fill" : "circle")
            .font(.subheadline.weight(.medium)).foregroundStyle(item.accepted ? PocketStyle.accent : .secondary).frame(minWidth: 94, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).accessibilityLabel("\(item.title)，\(item.accepted ? "已 AC，取消标记" : "未 AC，标记完成")").accessibilityIdentifier("plan-ac-\(item.id)")
        Spacer()
        Button { model.plans.toggle(item.id, favorite: true) } label: {
          Label(item.favorite ? "已收藏" : "收藏", systemImage: item.favorite ? "star.fill" : "star").font(.subheadline).foregroundStyle(item.favorite ? PocketStyle.amber : .secondary).frame(minWidth: 78, minHeight: 44, alignment: .trailing)
        }.buttonStyle(.plain).accessibilityLabel("\(item.title)，\(item.favorite ? "取消收藏" : "收藏")").accessibilityIdentifier("plan-star-\(item.id)")
      }.disabled(model.plans.busy).opacity(model.plans.busy ? 0.45 : 1)
    }.padding(16).background(PocketStyle.paper, in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(PocketStyle.line, lineWidth: 0.7) }
  }
}
