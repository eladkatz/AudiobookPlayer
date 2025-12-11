import SwiftUI
import Foundation

struct SleepTimerFullScreenView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea(.all)
                
                if isLandscape {
                    // Landscape: horizontal sections (left, center, right)
                    HStack(spacing: 0) {
                        // Left section: Stop button
                        stopButtonSection
                            .frame(width: geometry.size.width / 3)
                        
                        // Center section: Timer with ticks
                        timerSection(geometry: geometry)
                            .frame(width: geometry.size.width / 3)
                        
                        // Right section: Extend button
                        extendButtonSection
                            .frame(width: geometry.size.width / 3)
                    }
                } else {
                    // Portrait: vertical sections (left, center, right)
                    HStack(spacing: 0) {
                        // Left section: Stop button
                        stopButtonSection
                            .frame(width: geometry.size.width / 3)
                        
                        // Center section: Timer with ticks
                        timerSection(geometry: geometry)
                            .frame(width: geometry.size.width / 3)
                        
                        // Right section: Extend button
                        extendButtonSection
                            .frame(width: geometry.size.width / 3)
                    }
                }
            }
        }
    }
    
    // MARK: - Stop Button Section
    private var stopButtonSection: some View {
        Button(action: {
            audioManager.cancelSleepTimer()
        }) {
            VStack {
                Image(systemName: "stop.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23)) // #FF453A
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Timer Section
    private func timerSection(geometry: GeometryProxy) -> some View {
        let size = min(geometry.size.width / 3, geometry.size.height)
        
        return ZStack {
            // Circular tick indicator
            CircularTickIndicator(
                remainingSeconds: audioManager.sleepTimerRemaining,
                totalSeconds: audioManager.sleepTimerInitialDuration,
                size: size
            )
            
            // Countdown text
            Text(formatTimerTime(audioManager.sleepTimerRemaining))
                .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23)) // #FF453A
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Extend Button Section
    private var extendButtonSection: some View {
        Button(action: {
            audioManager.extendSleepTimer(additionalMinutes: 600) // 10 minutes
        }) {
            VStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23)) // #FF453A
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Helper Methods
    private func formatTimerTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Circular Tick Indicator
struct CircularTickIndicator: View {
    let remainingSeconds: TimeInterval
    let totalSeconds: TimeInterval
    let size: CGFloat
    
    private let numberOfTicks = 60
    private let tickLength: CGFloat // 6-8% of size
    private let tickThickness: CGFloat // 1.5-2px or ~1% of size
    private let outerRadius: CGFloat
    private let innerRadius: CGFloat
    
    init(remainingSeconds: TimeInterval, totalSeconds: TimeInterval, size: CGFloat) {
        self.remainingSeconds = remainingSeconds
        self.totalSeconds = totalSeconds
        self.size = size
        
        // Calculate tick dimensions
        self.tickLength = size * 0.07 // 7% of size
        self.tickThickness = max(size * 0.01, 2.0) // 1% of size, minimum 2px
        
        // Calculate radii
        self.outerRadius = size * 0.45 // 45% of size
        self.innerRadius = outerRadius - tickLength
    }
    
    var body: some View {
        ZStack {
            ForEach(0..<numberOfTicks, id: \.self) { index in
                TickView(
                    index: index,
                    totalTicks: numberOfTicks,
                    outerRadius: outerRadius,
                    innerRadius: innerRadius,
                    thickness: tickThickness,
                    containerSize: size,
                    isActive: isTickActive(index: index)
                )
            }
        }
        .frame(width: size, height: size)
    }
    
    private func isTickActive(index: Int) -> Bool {
        guard totalSeconds > 0 else { return false }
        
        let fraction = max(0, min(1, remainingSeconds / totalSeconds))
        let activeTicks = Int(round(fraction * Double(numberOfTicks)))
        
        // Ticks should be active (red) if they represent remaining time
        // Ticks start at top (index 0) and go clockwise
        // So remaining ticks should be at the END of the sequence
        // If we have 30 active ticks out of 60, ticks 30-59 should be red (remaining)
        // and ticks 0-29 should be gray (elapsed)
        let elapsedTicks = numberOfTicks - activeTicks
        return index >= elapsedTicks
    }
}

// MARK: - Individual Tick View
struct TickView: View {
    let index: Int
    let totalTicks: Int
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let thickness: CGFloat
    let containerSize: CGFloat
    let isActive: Bool
    
    private var angle: Double {
        // Start at top (-90°), go clockwise
        // Each tick is 6° apart (360° / 60)
        let angleStep = 360.0 / Double(totalTicks)
        return -90.0 + Double(index) * angleStep
    }
    
    private var outerPoint: CGPoint {
        let radians = angle * .pi / 180.0
        return CGPoint(
            x: outerRadius * CGFloat(cos(radians)),
            y: outerRadius * CGFloat(sin(radians))
        )
    }
    
    private var innerPoint: CGPoint {
        let radians = angle * .pi / 180.0
        return CGPoint(
            x: innerRadius * CGFloat(cos(radians)),
            y: innerRadius * CGFloat(sin(radians))
        )
    }
    
    private var center: CGFloat {
        containerSize / 2
    }
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(
                x: center + innerPoint.x,
                y: center + innerPoint.y
            ))
            path.addLine(to: CGPoint(
                x: center + outerPoint.x,
                y: center + outerPoint.y
            ))
        }
        .stroke(
            isActive ? activeColor : inactiveColor,
            style: StrokeStyle(
                lineWidth: thickness,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
    
    private var activeColor: Color {
        Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A
    }
    
    private var inactiveColor: Color {
        Color(red: 0.17, green: 0.17, blue: 0.18) // #2C2C2E
    }
}

