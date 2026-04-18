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
    @State private var showDeleteAccountConfirmation = false

    @State private var isAddingListInline = false
    @State private var newListName = ""
    @FocusState private var isListNameFieldFocused: Bool
    @State private var editingListID: PersistentIdentifier?
    @State private var editingListName = ""
    @FocusState private var isEditingListNameFocused: Bool

    let userEmail: String
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void
    var initialTab: Int = 0
    var initialCRMTab: Int = 0
    var autoSelectFirstList: Bool = false

    @State private var selectedTabIndex: Int = 0

    init(userEmail: String, onSignOut: @escaping () -> Void, onDeleteAccount: @escaping () -> Void,
         initialTab: Int = 0, initialCRMTab: Int = 0, autoSelectFirstList: Bool = false) {
        self.userEmail = userEmail
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        self.initialTab = initialTab
        self.initialCRMTab = initialCRMTab
        self.autoSelectFirstList = autoSelectFirstList
        self._selectedTabIndex = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTabIndex) {
            todoTab
                .tabItem { Label("To Do", systemImage: "checklist") }
                .tag(0)

            CRMRootView(initialCRMTab: initialCRMTab)
                .tabItem { Label("CRM", systemImage: "person.2.fill") }
                .tag(1)
        }
    }

    // MARK: - To Do Tab

    private var todoTab: some View {
        NavigationSplitView {
            List(selection: $selectedList) {
                Section {
                    inlineListInputRow
                }

                ForEach(lists) { list in
                    listRow(for: list)
                    .tag(list)
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingListDeletion = list
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
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
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Text(userEmail)
                        Button("Sign Out", role: .destructive, action: onSignOut)
                        Divider()
                        Button("Delete Account", role: .destructive) {
                            showDeleteAccountConfirmation = true
                        }
                    } label: {
                        Label("Account", systemImage: "person.circle")
                    }
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
                "Delete Account?",
                isPresented: $showDeleteAccountConfirmation
            ) {
                Button("Delete Account", role: .destructive, action: onDeleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All your lists and tasks will be permanently deleted. This cannot be undone.")
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

    @ViewBuilder
    private func listRow(for list: TodoList) -> some View {
        if editingListID == list.persistentModelID {
            HStack(spacing: 8) {
                TextField("List name", text: $editingListName)
                    .focused($isEditingListNameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitListRename(for: list) }

                Button("Save") {
                    commitListRename(for: list)
                }
                .disabled(editingListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelListRename()
                }
            }
            .onAppear {
                isEditingListNameFocused = true
            }
        } else {
            HStack {
                Text(list.name)
                    .onTapGesture {
                        beginListRename(for: list)
                    }
                Spacer()
                Text("\((list.tasks ?? []).filter { !$0.isCompleted }.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func createListInline() {
        let trimmedName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let nextOrder = (lists.map(\.sortOrder).min() ?? 1) - 1
        let list = TodoList(name: trimmedName, sortOrder: nextOrder)
        modelContext.insert(list)
        persistChanges()
        Task { await SupabaseService.shared.push(list: list) }

        cancelInlineListCreation()
    }

    private func beginListRename(for list: TodoList) {
        editingListID = list.persistentModelID
        editingListName = list.name
    }

    private func commitListRename(for list: TodoList) {
        let trimmed = editingListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        list.name = trimmed
        persistChanges()
        cancelListRename()
    }

    private func cancelListRename() {
        editingListID = nil
        editingListName = ""
        isEditingListNameFocused = false
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
        if editingListID == list.persistentModelID {
            cancelListRename()
        }
        let sid = list.supabaseId
        modelContext.delete(list)

        for (index, currentList) in lists.enumerated() {
            currentList.sortOrder = index
        }
        persistChanges()
        Task { await SupabaseService.shared.deleteList(sid) }
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

private struct TaskListDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let list: TodoList

    @State private var isAddingTaskInline = false
    @State private var newTaskTitle = ""
    @FocusState private var isTaskTitleFieldFocused: Bool

    @State private var pendingCompletionTask: TaskItem?
    @State private var pendingTaskDeletion: TaskItem?
    @State private var isCompletedExpanded = false
    @State private var editingTaskID: PersistentIdentifier?
    @State private var editingTaskTitle = ""
    @FocusState private var isEditingTaskTitleFocused: Bool

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

    private var completedTasks: [TaskItem] {
        allTasks.filter { $0.isCompleted }
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
                        .onMove(perform: moveCompletedTasks)
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .alert(
            "Mark task complete?",
            isPresented: Binding(
                get: { pendingCompletionTask != nil },
                set: { shouldShow in
                    if !shouldShow {
                        pendingCompletionTask = nil
                    }
                }
            ),
            presenting: pendingCompletionTask
        ) { task in
            Button("Confirm") {
                markTaskCompleted(task)
                pendingCompletionTask = nil
            }
            .accessibilityIdentifier("confirmCompleteTaskButton")

            Button("Cancel", role: .cancel) {
                pendingCompletionTask = nil
            }
        } message: { task in
            Text("\"\(task.title)\" will be moved to Completed.")
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
            if editingTaskID == task.persistentModelID {
                TextField("Task title", text: $editingTaskTitle)
                    .focused($isEditingTaskTitleFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTaskRename(for: task) }
                    .onAppear {
                        isEditingTaskTitleFocused = true
                    }
            } else {
                Text(task.title)
                    .onTapGesture {
                        beginTaskRename(for: task)
                    }
            }
            Spacer()
            if editingTaskID == task.persistentModelID {
                Button("Save") {
                    commitTaskRename(for: task)
                }
                .disabled(editingTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelTaskRename()
                }
            } else {
            Button {
                pendingCompletionTask = task
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark complete")
            .accessibilityIdentifier("markCompleteButton")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                pendingCompletionTask = task
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
        }
        .contextMenu {
            Button {
                pendingCompletionTask = task
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
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
            if editingTaskID == task.persistentModelID {
                TextField("Task title", text: $editingTaskTitle)
                    .focused($isEditingTaskTitleFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTaskRename(for: task) }
                    .onAppear {
                        isEditingTaskTitleFocused = true
                    }
            } else {
                Text(task.title)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        beginTaskRename(for: task)
                    }
            }
            Spacer()
            if editingTaskID == task.persistentModelID {
                Button("Save") {
                    commitTaskRename(for: task)
                }
                .disabled(editingTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelTaskRename()
                }
            } else {
            Button {
                moveTaskBackToActive(task)
            } label: {
                Label("Move Back", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move back to active")
            .accessibilityIdentifier("moveBackButton")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                moveTaskBackToActive(task)
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
        }
        .contextMenu {
            Button {
                moveTaskBackToActive(task)
            } label: {
                Label("Move Back", systemImage: "arrow.uturn.backward.circle")
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
        Task { await SupabaseService.shared.push(task: task) }

        cancelInlineTaskCreation()
    }

    private func beginTaskRename(for task: TaskItem) {
        editingTaskID = task.persistentModelID
        editingTaskTitle = task.title
    }

    private func commitTaskRename(for task: TaskItem) {
        let trimmed = editingTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        task.title = trimmed
        persistChanges()
        cancelTaskRename()
    }

    private func cancelTaskRename() {
        editingTaskID = nil
        editingTaskTitle = ""
        isEditingTaskTitleFocused = false
    }

    private func cancelInlineTaskCreation() {
        newTaskTitle = ""
        isAddingTaskInline = false
        isTaskTitleFieldFocused = false
    }

    private func markTaskCompleted(_ task: TaskItem) {
        task.completedAt = .now
        task.updatedAt   = .now
        persistChanges()
        Task { await SupabaseService.shared.push(task: task) }
    }

    private func moveTaskBackToActive(_ task: TaskItem) {
        task.completedAt = nil
        task.updatedAt   = .now
        persistChanges()
        Task { await SupabaseService.shared.push(task: task) }
    }

    private func deleteTask(_ task: TaskItem) {
        if editingTaskID == task.persistentModelID {
            cancelTaskRename()
        }
        let sid = task.supabaseId
        modelContext.delete(task)
        reindexTasks()
        persistChanges()
        Task { await SupabaseService.shared.deleteTask(sid) }
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

    private func moveCompletedTasks(from source: IndexSet, to destination: Int) {
        var reorderedCompleted = completedTasks
        reorderedCompleted.move(fromOffsets: source, toOffset: destination)

        var nextOrder = 0
        for task in activeTasks {
            task.sortOrder = nextOrder
            nextOrder += 1
        }

        for task in reorderedCompleted {
            task.sortOrder = nextOrder
            nextOrder += 1
        }
        persistChanges()
    }

    private func reindexTasks() {
        for (index, task) in allTasks.enumerated() {
            task.sortOrder = index
        }
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
    ContentView(userEmail: "preview@example.com", onSignOut: {}, onDeleteAccount: {}, initialTab: 0, initialCRMTab: 0, autoSelectFirstList: false)
        .modelContainer(for: [TodoList.self, TaskItem.self], inMemory: true)
}
