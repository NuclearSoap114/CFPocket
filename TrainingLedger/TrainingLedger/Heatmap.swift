import SwiftUI
import TrainingCore

struct TrainingHeatmap: View {
  let days: [TrainingDay]
  let year: Int
  let metric: HeatMetric
  @Binding var selected: Date?
  var ratingColors = false
  var framed = true
  var showsHeading = true
  @Environment(\.colorScheme) private var scheme
  private var dates: [Date] {
    let all = TrainingAnalysis.yearDates(year)
    return year == TrainingDates.calendar.component(.year, from: Date())
      ? all.filter { $0 <= TrainingDates.day(Date()) } : all
  }
  private var start: Date {
    let jan = dates[0]
    let c = TrainingDates.calendar
    let offset = (c.component(.weekday, from: jan) + 5) % 7
    return c.date(byAdding: .day, value: -offset, to: jan)!
  }
  private var dictionary: [Date: TrainingDay] {
    Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
  }
  private let cell: CGFloat = 12, gap: CGFloat = 4
  var body: some View {
    let dict = dictionary
    let first = start
    let calendar = TrainingDates.calendar
    let columns = (calendar.dateComponents([.day], from: first, to: dates.last!).day! + 7) / 7
    VStack(alignment: .leading, spacing: 12) {
      if showsHeading { HStack {
        Text("\(String(year)) 年训练记录").font(.headline)
        Spacer()
        Text(metric.rawValue).font(.caption).foregroundStyle(Theme.secondaryText)
      }
      }
      HStack(alignment: .top, spacing: 6) {
        VStack(spacing: 0) {
          Text(" ").font(.caption2).frame(height: 22)
          ForEach(0..<7, id: \.self) { i in
            Text(["一", "", "三", "", "五", "", ""][i]).font(.system(size: 9)).foregroundStyle(
              .secondary
            ).frame(width: 12, height: 16)
          }
        }
        ScrollView(.horizontal) {
          Canvas { context, size in
            for col in 0..<columns {
              let date = calendar.date(byAdding: .day, value: col * 7, to: first)!
              if col == 0
                || calendar.component(.month, from: date)
                  != calendar.component(
                    .month, from: calendar.date(byAdding: .day, value: -7, to: date)!)
              {
                let text = Text("\(calendar.component(.month,from:date))月").font(.system(size: 10))
                  .foregroundStyle(Color(uiColor: .secondaryLabel))
                context.draw(text, at: CGPoint(x: CGFloat(col) * 16 + 7, y: 9), anchor: .center)
              }
              for row in 0..<7 {
                let d = calendar.date(byAdding: .day, value: col * 7 + row, to: first)!
                guard calendar.component(.year, from: d) == year else { continue }
                let count = dict[d]?.count(metric) ?? 0
                let rect = CGRect(
                  x: CGFloat(col) * 16, y: CGFloat(row) * 16 + 24, width: cell, height: cell)
                let future = d > TrainingDates.day(Date())
                let color =
                  count == 0
                  ? Color(uiColor: scheme == .dark ? .tertiarySystemFill : .systemGray5)
                  : (ratingColors ? Theme.rating(.band(dict[d]?.hardest?.value)) : Theme.accent)
                    .opacity(count < 2 ? 0.38 : count < 4 ? 0.56 : count < 8 ? 0.78 : 1)
                context.fill(
                  Path(roundedRect: rect, cornerRadius: 3),
                  with: .color(color.opacity(future ? 0.35 : 1)))
                if selected.map(TrainingDates.day) == d {
                  context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 4),
                    with: .color(.primary), lineWidth: 1.5)
                }
              }
            }
          }.frame(width: CGFloat(columns) * 16, height: 136).contentShape(Rectangle())
            .onTapGesture { location in
              let col = Int(location.x / 16)
              let row = Int((location.y - 24) / 16)
              guard col >= 0, col < columns, row >= 0, row < 7, location.y >= 24 else { return }
              let date = calendar.date(byAdding: .day, value: col * 7 + row, to: first)!
              guard calendar.component(.year, from: date) == year, date <= TrainingDates.day(Date())
              else { return }
              selected = date
            }
            .accessibilityLabel("\(year)年训练热力图，\(days.count)个有记录的日期。可使用下方日期选择器查看具体题目。")
        }.scrollIndicators(.hidden).defaultScrollAnchor(.trailing)
      }
      HStack(spacing: 5) {
        Text("少")
        ForEach([0.0, 0.38, 0.56, 0.78, 1.0], id: \.self) { v in
          RoundedRectangle(cornerRadius: 2).fill(
            v == 0 ? Color(uiColor: .systemGray5) : Theme.accent.opacity(v)
          ).frame(width: 10, height: 10)
        }
        Text("多")
        Spacer()
        Text("点击日期查看题目")
      }.font(.caption2).foregroundStyle(Theme.secondaryText)
      if ratingColors {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)], alignment: .leading, spacing: 8) {
          ForEach(CFRatingBand.allCases) { band in
            Label { Text(band.label).fixedSize(horizontal: false, vertical: true) } icon: {
              Circle().fill(Theme.rating(band)).frame(width: 8, height: 8)
            }.font(.caption2).foregroundStyle(Theme.secondaryText)
          }
        }
        Text("色相：当天AC题最高rating；深浅：\(metric.rawValue)。未采集到AC难度时用灰色。").font(.caption2).foregroundStyle(Theme.secondaryText)
      }
    }.padding(framed ? 18 : 0).background(Color(uiColor: .secondarySystemGroupedBackground).opacity(framed ? 1 : 0), in: RoundedRectangle(cornerRadius: 24))
  }
}
struct MiniHeatmap: View {
  let days: [TrainingDay]
  var body: some View {
    let counts = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.submissions) })
    let c = TrainingDates.calendar
    let today = TrainingDates.day(Date())
    HStack(spacing: 3) {
      ForEach((-27)...0, id: \.self) { offset in
        let d = c.date(byAdding: .day, value: offset, to: today)!
        let n = counts[d] ?? 0
        RoundedRectangle(cornerRadius: 2).fill(
          n == 0
            ? Color(uiColor: .systemGray5) : Theme.accent.opacity(n < 3 ? 0.4 : n < 6 ? 0.7 : 1)
        ).frame(height: 10)
      }
    }.accessibilityLabel("最近28天的已采集提交分布")
  }
}
