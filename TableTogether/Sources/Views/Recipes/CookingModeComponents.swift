import SwiftUI

// MARK: - Timer Picker Sheet

struct TimerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var seconds: Int
    let onStart: () -> Void

    @State private var selectedMinutes: Int = 5

    let minuteOptions = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Set Timer")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Quick select buttons
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(minuteOptions, id: \.self) { minutes in
                        Button {
                            selectedMinutes = minutes
                        } label: {
                            Text("\(minutes) min")
                                .font(.subheadline)
                                .fontWeight(selectedMinutes == minutes ? .bold : .regular)
                                .foregroundColor(selectedMinutes == minutes ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedMinutes == minutes ? Color.accentColor : Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Custom picker
                #if os(iOS)
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(1...60, id: \.self) { minute in
                        Text("\(minute) minutes").tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                #endif

                // Start button
                Button {
                    seconds = selectedMinutes * 60
                    onStart()
                    dismiss()
                } label: {
                    Text("Start Timer")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
