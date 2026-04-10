import SwiftUI

struct FilterView: View {
    @ObservedObject var vm: ContactsViewModel
    let contacts: [Contact]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Priority") {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Button(action: {
                            vm.selectedPriority = vm.selectedPriority == p ? nil : p
                        }) {
                            HStack {
                                PriorityBadge(priority: p)
                                Spacer()
                                if vm.selectedPriority == p {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color("AccentColor"))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                let tags = vm.allTags(in: contacts)
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            Button(action: {
                                vm.selectedTag = vm.selectedTag == tag ? nil : tag
                            }) {
                                HStack {
                                    TagChip(tag: tag)
                                    Spacer()
                                    if vm.selectedTag == tag {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color("AccentColor"))
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                let cities = vm.allCities(in: contacts)
                if !cities.isEmpty {
                    Section("City") {
                        ForEach(cities, id: \.self) { city in
                            Button(action: {
                                vm.selectedCity = vm.selectedCity == city ? nil : city
                            }) {
                                HStack {
                                    Label(city, systemImage: "mappin")
                                    Spacer()
                                    if vm.selectedCity == city {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color("AccentColor"))
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Button("Clear All Filters", role: .destructive) {
                        vm.selectedPriority = nil
                        vm.selectedTag = nil
                        vm.selectedCity = nil
                        dismiss()
                    }
                }
            }
            .navigationTitle("Filter Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
