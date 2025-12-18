import SwiftUI

struct ChaptersListView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var audioManager = AudioManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if audioManager.chapters.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No chapters available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(audioManager.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(action: {
                                audioManager.seek(to: chapter.startTime)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chapter.title)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text(formatTime(chapter.startTime))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if index == audioManager.currentChapterIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding()
                                .background(
                                    index == audioManager.currentChapterIndex
                                        ? Color.blue.opacity(0.1)
                                        : Color(.systemGray6)
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}


