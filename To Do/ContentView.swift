//
//  ContentView.swift
//  To Do
//
//  Created by Mukul Arora on 28/02/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\TodoList.sortOrder, order: .forward),
            SortDescriptor(\TodoList.createdAt, order: .forward)
        ]
    )
    private var lists: [TodoList]

    @State private var selectedList: TodoList?
    @State private var pendingListDeletion: TodoList?
    @State private var showEraseDataConfirmation = false

    @State private var isAddingListInline = false
    @State private var newListName = ""
    @FocusState private var isListNameFieldFocused: Bool
    @State private var renamingList: TodoList?

    let onEraseAllData: () -> Void
    var initialTab: Int = 0
    var initialCRMTab: Int = 0
    var autoSelectFirstList: Bool = false

    @State private var selectedTabIndex: Int = 0

    init(onEraseAllData: @escaping () -> Void,
         initialTab: Int = 0, initialCRMTab: Int = 0, autoSelectFirstList: Bool = false) {
        self.onEraseAllData = onEraseAllData
        self.initialTab = initialTab
        self.initialCRMTab = initialCRMTab
        self.autoSelectFirstList = autoSelectFirstList
        self._selectedTabIndex = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTabIndex) {
            todoTab
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(0)

            CRMRootView(initialCRMTab: initialCRMTab)
                .tabItem { Label("People", systemImage: "person.2.fill") }
                .tag(1)
        }
    }

    // MARK: - Tasks Tab

    private var todoTab: some View {
        NavigationSplitView {
            List(selection: $selectedList) {
                Section {
                    inlineListInputRow
                }

                ForEach(lists) { list in
                    listRow(for: list)
                    .tag(list)
                    .swipeActions(edge: .leading) {
                        Button {
                            renamingList = list
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingListDeletion = list
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            renamingList = list
                        } label: {
                            Label("Rename List", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            pendingListDeletion = list
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveLists)
            }
            .navigationTitle("Lists")
            .task {
                if autoSelectFirstList, selectedList == nil {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    selectedList = lists.first
                }
            }
            .toolbar {
                // Without this, the .onMove above has no affordance — reordering was
                // implemented but unreachable.
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .accessibilityIdentifier("editListsButton")
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(role: .destructive) {
                            showEraseDataConfirmation = true
                        } label: {
                            Label("Erase All Data", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("moreMenuButton")
                }
            }
            .sheet(item: $renamingList) { list in
                RenameSheet(title: "Rename List", name: list.name) { newName in
                    list.name = newName
                    persistChanges()
                }
            }
            .confirmationDialog(
                "Delete this list?",
                isPresented: Binding(
                    get: { pendingListDeletion != nil },
                    set: { shouldShow in
                        if !shouldShow {
                            pendingListDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    guard let list = pendingListDeletion else { return }
                    deleteList(list)
                    pendingListDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingListDeletion = nil
                }
            } message: {
                Text("All tasks in this list will also be deleted.")
            }
            .alert(
                "Erase All Data?",
                isPresented: $showEraseDataConfirmation
            ) {
                Button("Erase Everything", role: .destructive, action: onEraseAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All your lists, tasks, contacts, and interaction history will be permanently deleted from this device and from iCloud. This cannot be undone.")
            }
            .onChange(of: lists) { _, updatedLists in
                if updatedLists.isEmpty {
                    selectedList = nil
                    return
                }

                if let selectedList,
                   updatedLists.contains(where: { $0.persistentModelID == selectedList.persistentModelID }) {
                    return
                }
                self.selectedList = nil
            }
        } detail: {
            if let selectedList {
                TaskListDetailView(list: selectedList)
            } else {
                ContentUnavailableView(
                    "No List Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a list to start tracking tasks.")
                )
            }
        }
    }

    @ViewBuilder
    private var inlineListInputRow: some View {
        if isAddingListInline {
            HStack(spacing: 8) {
                TextField("New List", text: $newListName)
                    .focused($isListNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createListInline)
                    .accessibilityIdentifier("newListInlineField")

                Button("Add", action: createListInline)
                    .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelInlineListCreation()
                }
            }
            .onAppear {
                isListNameFieldFocused = true
            }
        } else {
            Button {
                isAddingListInline = true
            } label: {
                Label("New List", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("newListRowTrigger")
        }
    }

    /// Tapping a row selects the list. Renaming lives in the swipe action and context menu
    /// instead of an `onTapGesture` on the name, which used to swallow the selection tap.
    private func listRow(for list: TodoList) -> some View {
        HStack {
            Text(list.name)
            Spacer()
            Text("\((list.tasks ?? []).filter { !$0.isCompleted }.count)")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func createListInline() {
        let trimmedName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let nextOrder = (lists.map(\.sortOrder).min() ?? 1) - 1
        let list = TodoList(name: trimmedName, sortOrder: nextOrder)
        modelContext.insert(list)
        persistChanges()

        cancelInlineListCreation()
    }

    private func cancelInlineListCreation() {
        newListName = ""
        isAddingListInline = false
        isListNameFieldFocused = false
    }

    private func deleteList(_ list: TodoList) {
        if selectedList?.persistentModelID == list.persistentModelID {
            selectedList = nil
        }
        modelContext.delete(list)

        // Reindex from the surviving lists. Iterating the @Query array here would still
        // include the list just deleted, since it has not refreshed yet.
        for (index, currentList) in lists.filter({ $0.persistentModelID != list.persistentModelID }).enumerated() {
            currentList.sortOrder = index
        }
        persistChanges()
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var reorderedLists = lists
        reorderedLists.move(fromOffsets: source, toOffset: destination)

        for (index, list) in reorderedLists.enumerated() {
            list.sortOrder = index
        }
        persistChanges()
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save list changes: \(error.localizedDescription)")
        }
    }
}

// MARK: - Rename Sheet

/// Renaming in a sheet rather than inline. The inline editor put Save and Cancel buttons
/// into the row itself, which clipped badly at large Dynamic Type sizes.
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @State private var name: String
    let onSave: (String) -> Void

    @FocusState private var isFocused: Bool

    init(title: String, name: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self._name = State(initialValue: name)
        self.onSave = onSave
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier("renameField")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.height(180)])
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

// MARK: - Task List Detail

private struct TaskListDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let list: TodoList

    @State private var isAddingTaskInline = false
    @State private var newTaskTitle = ""
    @FocusState private var isTaskTitleFieldFocused: Bool

    @State private var pendingTaskDeletion: TaskItem?
    @State private var isCompletedExpanded = false
    @State private var renamingTask: TaskItem?

    /// The task completed most recently, so it can be undone. Cleared once the user does
    /// anything else, so Undo never applies to something older than the last action.
    @State private var lastCompletedTask: TaskItem?

    private var allTasks: [TaskItem] {
        (list.tasks ?? [])
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var activeTasks: [TaskItem] {
        allTasks.filter { !$0.isCompleted }
    }

    /// Most recently completed first — `completedAt` was already recorded but never used
    /// for ordering, so the newest completion could land anywhere in the list.
    private var completedTasks: [TaskItem] {
        allTasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section("To Do") {
                inlineTaskInputRow

                if activeTasks.isEmpty {
                    Text("No tasks yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeTasks) { task in
                        taskRow(task)
                    }
                    .onMove(perform: moveActiveTasks)
                }
            }

            Section {
                DisclosureGroup("Completed", isExpanded: $isCompletedExpanded) {
                    if completedTasks.isEmpty {
                        Text("Completed tasks will appear here")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(completedTasks) { task in
                            completedTaskRow(task)
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .accessibilityIdentifier("editTasksButton")
            }
        }
        .safeAreaInset(edge: .bottom) {
            undoBar
        }
        .sheet(item: $renamingTask) { task in
            RenameSheet(title: "Rename Task", name: task.title) { newTitle in
                task.title = newTitle
                persistChanges()
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: Binding(
                get: { pendingTaskDeletion != nil },
                set: { shouldShow in
                    if !shouldShow {
                        pendingTaskDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                guard let task = pendingTaskDeletion else { return }
                deleteTask(task)
                pendingTaskDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                pendingTaskDeletion = nil
            }
        }
    }

    /// Replaces the confirmation alert that used to gate every completion. Completing is
    /// one tap and reversible from here.
    @ViewBuilder
    private var undoBar: some View {
        if let task = lastCompletedTask, task.isCompleted {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Completed \"\(task.title)\"")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Button("Undo") {
                    withAnimation {
                        moveTaskBackToActive(task)
                        lastCompletedTask = nil
                    }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("undoCompleteButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var inlineTaskInputRow: some View {
        if isAddingTaskInline {
            HStack(spacing: 8) {
                TextField("New Task", text: $newTaskTitle)
                    .focused($isTaskTitleFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createTaskInline)
                    .accessibilityIdentifier("newTaskInlineField")

                Button("Add", action: createTaskInline)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelInlineTaskCreation()
                }
            }
            .onAppear {
                isTaskTitleFieldFocused = true
            }
        } else {
            Button {
                isAddingTaskInline = true
            } label: {
                Label("New Task", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("newTaskRowTrigger")
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack {
            Button {
                complete(task)
            } label: {
                Image(systemName: "circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark complete")
            .accessibilityIdentifier("markCompleteButton")

            Text(task.title)
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button {
                complete(task)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        .swipeActions {
            Button(role: .destructive) {
                pendingTaskDeletion = task
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                renamingTask = task
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                complete(task)
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
            }

            Button {
                renamingTask = task
            } label: {
                Label("Rename Task", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingTaskDeletion = task
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private func completedTaskRow(_ task: TaskItem) -> some View {
        HStack {
            Button {
                withAnimation { moveTaskBackToActive(task) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move back to active")
            .accessibilityIdentifier("moveBackButton")

            Text(task.title)
                .strikethrough()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button {
                withAnimation { moveTaskBackToActive(task) }
            } label: {
                Label("Move Back", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(.orange)
        }
        .swipeActions {
            Button(role: .destructive) {
                pendingTaskDeletion = task
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                renamingTask = task
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                withAnimation { moveTaskBackToActive(task) }
            } label: {
                Label("Move Back", systemImage: "arrow.uturn.backward.circle")
            }

            Button {
                renamingTask = task
            } label: {
                Label("Rename Task", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingTaskDeletion = task
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private func createTaskInline() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let nextOrder = ((list.tasks ?? []).map(\.sortOrder).min() ?? 1) - 1
        let task = TaskItem(title: trimmedTitle, list: list, sortOrder: nextOrder)
        modelContext.insert(task)
        persistChanges()

        cancelInlineTaskCreation()
    }

    private func cancelInlineTaskCreation() {
        newTaskTitle = ""
        isAddingTaskInline = false
        isTaskTitleFieldFocused = false
    }

    private func complete(_ task: TaskItem) {
        withAnimation {
            task.completedAt = .now
            lastCompletedTask = task
            persistChanges()
        }
    }

    private func moveTaskBackToActive(_ task: TaskItem) {
        task.completedAt = nil
        if lastCompletedTask?.persistentModelID == task.persistentModelID {
            lastCompletedTask = nil
        }
        persistChanges()
    }

    private func deleteTask(_ task: TaskItem) {
        if lastCompletedTask?.persistentModelID == task.persistentModelID {
            lastCompletedTask = nil
        }
        modelContext.delete(task)

        // Reindex from the surviving tasks; `allTasks` still contains the deleted one.
        for (index, remaining) in allTasks.filter({ $0.persistentModelID != task.persistentModelID }).enumerated() {
            remaining.sortOrder = index
        }
        persistChanges()
    }

    private func moveActiveTasks(from source: IndexSet, to destination: Int) {
        var reordered = activeTasks
        reordered.move(fromOffsets: source, toOffset: destination)

        var nextOrder = 0
        for task in reordered {
            task.sortOrder = nextOrder
            nextOrder += 1
        }

        for task in completedTasks {
            task.sortOrder = nextOrder
            nextOrder += 1
        }
        persistChanges()
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save task changes: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView(onEraseAllData: {})
        .modelContainer(for: [TodoList.self, TaskItem.self], inMemory: true)
}
