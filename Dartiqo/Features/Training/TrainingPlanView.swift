import SwiftUI
import Charts

struct TrainingPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var goal: TrainingGoal = .complete
    @State private var span = 7
    @State private var days = 3
    @State private var minutes = 10
    @State private var level: TrainingLevel = .advanced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let plan = store.currentTrainingPlan {
                    planCard(plan)
                }
                form
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Plán")
    }

    private func planCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.goal.title).font(AppFont.title(20))
            Text("\(plan.span) dní · \(plan.daysPerWeek)× týdně · \(plan.minutes) min · \(plan.level.title)")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
            ForEach(plan.items) { item in
                if let definition = TrainingCatalog.find(item.definitionID) {
                    HStack {
                        Image(systemName: item.sessionID == nil ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(item.sessionID == nil ? .secondary : Theme.positive)
                        VStack(alignment: .leading) {
                            Text("Den \(item.day + 1)").font(AppFont.caption()).foregroundStyle(.secondary)
                            Text(definition.title).font(AppFont.body(16, weight: .semibold))
                        }
                        Spacer()
                        if item.sessionID == nil {
                            NavigationLink("Hrát") { TrainingSetupView(definition: definition) }
                                .font(AppFont.caption())
                        }
                    }
                }
            }
        }
        .surface()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.currentTrainingPlan == nil ? "Nový plán" : "Nový plán nahradí stávající")
                .font(AppFont.body(16, weight: .semibold))
            Picker("Cíl", selection: $goal) {
                ForEach(TrainingGoal.allCases) { item in Text(item.title).tag(item) }
            }
            Picker("Délka", selection: $span) {
                Text("7 dní").tag(7)
                Text("30 dní").tag(30)
            }
            .pickerStyle(.segmented)
            Stepper("Dní v týdnu: \(days)", value: $days, in: 1...7)
            Stepper("Délka session: \(minutes) min", value: $minutes, in: 5...40, step: 5)
            Picker("Úroveň", selection: $level) {
                ForEach(TrainingLevel.allCases) { item in Text(item.title).tag(item) }
            }
            Button("Sestavit plán") { build() }
                .buttonStyle(PrimaryButton())
        }
        .surface()
    }

    private func build() {
        guard let owner = store.profile?.id else { return }
        let plan = TrainingPlans.make(goal: goal, span: span, daysPerWeek: days, minutes: minutes, level: level, owner: owner)
        store.saveTrainingPlan(plan)
    }
}

struct TrainingChartsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days = 30

    private var points: [TrainingDayPoint] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        let sessions = store.trainingHistory.filter { ($0.finishedAt ?? $0.startedAt) >= start && $0.status == .completed }
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.finishedAt ?? $0.startedAt) }
        return grouped.keys.sorted().map { day in
            let rows = grouped[day] ?? []
            let accuracy = rows.isEmpty ? 0 : rows.reduce(0) { $0 + ($1.result?.accuracy ?? 0) } / Double(rows.count)
            let averages = rows.compactMap { $0.result?.average }
            let average = averages.isEmpty ? nil : averages.reduce(0, +) / Double(averages.count)
            return TrainingDayPoint(day: day, accuracy: accuracy, average: average)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Období", selection: $days) {
                    Text("7 dní").tag(7)
                    Text("30 dní").tag(30)
                    Text("90 dní").tag(90)
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    EmptyCard(title: "Málo dat", subtitle: "Graf se vykreslí z dokončených tréninků v tomhle okně.", symbol: "chart.xyaxis.line")
                } else {
                    chart("Přesnost", points.compactMap { point in
                        Optional((point.day, point.accuracy * 100))
                    }, suffix: " %")
                    let averages = points.compactMap { point -> (Date, Double)? in
                        guard let average = point.average else { return nil }
                        return (point.day, average)
                    }
                    if !averages.isEmpty {
                        chart("Průměr", averages, suffix: "")
                    }
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Vývoj")
    }

    private func chart(_ title: String, _ rows: [(Date, Double)], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppFont.body(16, weight: .bold))
            Chart(rows, id: \.0) { row in
                LineMark(x: .value("Den", row.0, unit: .day), y: .value(title, row.1))
                PointMark(x: .value("Den", row.0, unit: .day), y: .value(title, row.1))
            }
            .frame(height: 180)
            if let last = rows.last {
                Text("Poslední \(Int(last.1.rounded()))\(suffix)")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .surface()
    }
}

struct TrainingDayPoint: Identifiable {
    var day: Date
    var accuracy: Double
    var average: Double?
    var id: Date { day }
}
