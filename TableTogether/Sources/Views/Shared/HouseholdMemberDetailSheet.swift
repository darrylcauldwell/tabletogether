#if os(iOS)
import SwiftUI
import CloudKit

/// Detail sheet for a single household participant.
///
/// Surfaces the recipient identifier (name / email / phone), the current acceptance
/// status, and the actions the owner can take: resend the invite (re-presents the
/// share sheet) or revoke it (per-participant removal from the underlying CKShare).
struct HouseholdMemberDetailSheet: View {
    let member: PersistenceController.HouseholdMember
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingRemoveConfirmation = false

    private var persistenceController: PersistenceController { PersistenceController.shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: member.status.iconName)
                            .font(.system(size: 44))
                            .foregroundStyle(member.status == .accepted ? Theme.Colors.primary : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(member.status.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if member.email != nil || member.phone != nil {
                    Section("Contact") {
                        if let email = member.email {
                            LabeledContent("Email") {
                                Text(email)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        if let phone = member.phone {
                            LabeledContent("Phone") {
                                Text(phone)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                } else if member.status == .pending {
                    Section {
                        Text("Contact details aren't available until the invitee accepts the invitation.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                if member.status == .pending, let share = persistenceController.existingShare {
                    Section {
                        ShareLink(
                            item: share,
                            preview: SharePreview("TableTogether Household")
                        ) {
                            Label("Resend Invite", systemImage: "paperplane")
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text("Re-opens the share sheet so you can send the invitation link again via Messages, Mail, or another channel.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        Label(member.status == .pending ? "Revoke Invite" : "Remove from Household",
                              systemImage: "person.badge.minus")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(member.status == .pending
                         ? "The invitation link will stop working. You can invite this person again later."
                         : "\(member.name) will lose access to your shared meal plans, recipes, and grocery lists.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Household Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onClose()
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .confirmationDialog(
                member.status == .pending ? "Revoke Invite?" : "Remove from Household?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button(member.status == .pending ? "Revoke" : "Remove", role: .destructive) {
                    removeMember()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(member.status == .pending
                     ? "The invitation link for \(member.name) will stop working."
                     : "\(member.name) will lose access to your shared household.")
            }
        }
    }

    private func removeMember() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await persistenceController.removeParticipant(matching: member.id)
                isWorking = false
                dismiss()
                onClose()
            } catch {
                isWorking = false
                errorMessage = "Couldn't remove: \(error.localizedDescription)"
            }
        }
    }
}
#endif
