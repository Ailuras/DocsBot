import SwiftUI
import EventKit
import FacetXCore

struct ItemDetailPane: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    let item: ProjectItem
    let project: Project
    let onClose: () -> Void
    let onUpdate: () -> Void

    @State private var content = ""
    @State private var notes = ""
    @State private var priority = 0
    @State private var useDate = false
    @State private var date = Date()
    @State private var urlString = ""
    @State private var containerName = ""
    @State private var saving = false

    private let labelWidth: CGFloat = 82
    private let controlWidth: CGFloat = 184

    private var hasChanges: Bool {
        if content.trimmingCharacters(in: .whitespaces) != item.content { return true }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines) != (item.notes ?? "") { return true }
        if priority != item.priority { return true }
        let itemHasDate = item.date != nil
        if item.kind == .reminder, useDate != itemHasDate { return true }
        if (item.kind == .event || useDate),
           let d = item.date,
           Calendar.current.compare(date, to: d, toGranularity: .minute) != .orderedSame { return true }
        if containerName != item.containerName { return true }
        if urlString.trimmingCharacters(in: .whitespaces) != (item.url?.absoluteString ?? "") { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleCard
                    propertyCard
                    notesCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 10) {
            Label {
                Text(item.kind == .reminder ? "Reminder" : "Event")
            } icon: {
                Image(systemName: item.kind == .reminder ? "checklist" : "calendar")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close sidebar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.kind == .reminder ? Color.green.opacity(0.14) : Color.blue.opacity(0.14))
                    Image(systemName: item.kind == .reminder ? "checkmark.circle" : "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.kind == .reminder ? .green : .blue)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    TextField("What needs doing?", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1...4)

                    Text("\(project.name) · \(containerName.isEmpty ? item.containerName : containerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var propertyCard: some View {
        VStack(spacing: 0) {
            propertyRow(label: item.kind == .reminder ? "List" : "Calendar",
                        icon: item.kind == .reminder ? "list.bullet" : "calendar") {
                Picker("", selection: $containerName) {
                    ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: controlWidth, alignment: .trailing)
            }

            if item.kind == .reminder {
                propertyDivider
                propertyRow(label: "Priority", icon: "exclamationmark.circle") {
                    PriorityPillPicker(selection: $priority)
                        .frame(width: controlWidth)
                }
            }

            propertyDivider
            propertyRow(label: item.kind == .reminder ? "Due Date" : "Start",
                        icon: "calendar") {
                dateControl
                    .frame(width: controlWidth, alignment: .trailing)
            }

            propertyDivider
            propertyRow(label: "URL", icon: "link") {
                HStack(spacing: 6) {
                    TextField("Link associated...", text: $urlString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(FacetTheme.panel.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(FacetTheme.hairline, lineWidth: 1)
                        )

                    if let parsedURL = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
                       !urlString.trimmingCharacters(in: .whitespaces).isEmpty {
                        Link(destination: parsedURL) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open link")
                    }
                }
                .frame(width: controlWidth)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add notes and details here...")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(minHeight: 210)
            }
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
    }

    private var dateControl: some View {
        HStack(spacing: 8) {
            if item.kind == .event {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
            } else if useDate {
                DatePicker("", selection: $date,
                           displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
            } else {
                Text("No date")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            if item.kind == .reminder {
                Toggle("", isOn: $useDate)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var propertyDivider: some View {
        Divider()
            .padding(.leading, labelWidth + 12)
            .opacity(0.38)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                deleteItem()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.82))
                    .frame(width: 30, height: 28)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Delete item")

            Spacer()

            Button {
                saveChanges()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasChanges || content.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FacetTheme.canvas)
    }

    private func propertyRow<Control: View>(label: String, icon: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 13)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: labelWidth, alignment: .leading)

            control()
                .frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private var containerOptions: [String] {
        switch item.kind {
        case .reminder:
            return ek.reminderListNames(enabled: settings.enabledReminderListNames)
        case .event:
            return ek.calendarNames(enabled: settings.enabledCalendarNames)
        }
    }

    private func loadFields() {
        content = item.content
        notes = item.notes ?? ""
        priority = item.priority
        containerName = item.containerName
        urlString = item.url?.absoluteString ?? ""
        if item.kind == .event {
            useDate = true
            date = item.date ?? Date()
        } else if let d = item.date {
            useDate = true
            date = d
        } else {
            useDate = false
            date = Date()
        }
    }

    private func saveChanges() {
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !containerName.isEmpty else { return }

        saving = true
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let urlParam = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
        let shouldUseDate = item.kind == .event || useDate

        Task {
            let ok = await ek.updateItem(id: item.id, project: project.prefix, content: text,
                                         date: shouldUseDate ? date : nil, useDate: shouldUseDate,
                                         containerName: containerName,
                                         notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                                         priority: priority, url: urlParam, updateURL: true)
            saving = false
            if ok { onUpdate() }
        }
    }

    private func deleteItem() {
        saving = true
        Task {
            let ok = await ek.deleteItem(id: item.id)
            saving = false
            if ok {
                onUpdate()
                onClose()
            }
        }
    }
}
