import SwiftUI
import EventKit

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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label(item.kind == .reminder ? "Reminder" : "Event",
                      systemImage: item.kind == .reminder ? "list.bullet" : "calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title").font(.caption).foregroundStyle(.secondary)
                        TextField("What needs doing?", text: $content, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    // Container (List or Calendar)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kind == .reminder ? "Reminder List" : "Calendar").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $containerName) {
                            ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Priority (Reminder only)
                    if item.kind == .reminder {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Priority").font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $priority) {
                                Text("None").tag(0)
                                Text("Low").tag(9)
                                Text("Medium").tag(5)
                                Text("High").tag(1)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    // Date picker
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(item.kind == .reminder ? "Due Date" : "Start Date", isOn: $useDate)
                            .font(.caption).foregroundStyle(.secondary)
                        
                        if useDate {
                            DatePicker("", selection: $date,
                                       displayedComponents: item.kind == .reminder ? [.date] : [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // URL
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("URL").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let parsedURL = URL(string: urlString.trimmingCharacters(in: .whitespaces)), !urlString.isEmpty {
                                Link(destination: parsedURL) {
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        TextField("https://...", text: $urlString)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    // Notes / Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .padding(6)
                            .frame(minHeight: 150)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
    }
    
    private var containerOptions: [String] {
        switch item.kind {
        case .reminder:
            return ek.reminderListNames(enabled: settings.enabledContainerNames)
        case .event:
            return ek.calendarNames(enabled: settings.enabledContainerNames)
        }
    }
    
    private func loadFields() {
        content = item.content
        notes = item.notes ?? ""
        priority = item.priority
        containerName = item.containerName
        urlString = item.url?.absoluteString ?? ""
        if let d = item.date {
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
        let urlParam = URL(string: urlString.trimmingCharacters(in: .whitespaces))
        
        let ok = ek.updateItem(id: item.id, project: project.prefix, content: text,
                               date: useDate ? date : nil, useDate: useDate,
                               containerName: containerName, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                               priority: priority, url: urlParam)
        saving = false
        if ok {
            onUpdate()
        }
    }
    
    private func deleteItem() {
        saving = true
        let ok = ek.deleteItem(id: item.id)
        saving = false
        if ok {
            onUpdate()
            onClose()
        }
    }
}
