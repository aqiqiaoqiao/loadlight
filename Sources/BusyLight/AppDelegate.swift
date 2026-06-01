import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var cpuMenuItem: NSMenuItem!
    private var gpuMenuItem: NSMenuItem!
    private var stateMenuItem: NSMenuItem!

    private let monitor = MonitorEngine(
        cpuBusyThreshold: 0.65,
        gpuBusyThreshold: 70,
        debounceCount: 3
    )

    // Breathing state
    private var breathTimer: Timer?
    private var breathPhase: CGFloat = 1.0
    private var breathStart: CFTimeInterval = 0

    // Piecewise breathing: fade-in (0.5s) → hold-bright (0.5s) → fade-out (0.5s) → loop
    private let fadeInDuration: CFTimeInterval = 0.5
    private let holdBrightDuration: CFTimeInterval = 0.5
    private let fadeOutDuration: CFTimeInterval = 0.5
    private var breathCycleDuration: CFTimeInterval { fadeInDuration + holdBrightDuration + fadeOutDuration }

    // Display throttle — only redraw when phase actually changes
    private var lastDrawnPhase: CGFloat = -1.0

    // Current visual state
    private var isBusy = false
    private var lightColor: LightColor = .green

    // Track when red started, for "red ≥1 min → green" sound alert
    private var redStartedAt: Date?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupMonitor()
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("⚠️ Notification permission denied: \(error)")
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = LightRenderer.makeImage(on: true, color: .green)
            button.imagePosition = .imageOnly
            button.toolTip = "BusyLight — Idle"
        }

        let menu = NSMenu()
        stateMenuItem = NSMenuItem(title: "State: Idle", action: nil, keyEquivalent: "")
        menu.addItem(stateMenuItem)
        cpuMenuItem = NSMenuItem(title: "CPU: --%", action: nil, keyEquivalent: "")
        menu.addItem(cpuMenuItem)
        gpuMenuItem = NSMenuItem(title: "GPU: --%", action: nil, keyEquivalent: "")
        menu.addItem(gpuMenuItem)
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "CPU > 65% or GPU > 70% → red", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Monitor

    private func setupMonitor() {
        monitor.onStatusUpdate = { [weak self] light, cpu, gpu in
            guard let self else { return }
            let busy = (light == .red)
            DispatchQueue.main.async {
                self.stateChanged(busy: busy, cpu: cpu, gpu: gpu)
            }
        }
        monitor.start()
    }

    private func stateChanged(busy: Bool, cpu: Double, gpu: Int) {
        let color: LightColor = busy ? .red : .green

        if busy != isBusy {
            isBusy = busy
            lightColor = color

            if busy {
                // ── Turned red: start tracking duration ──
                redStartedAt = Date()
                startBreathing()
            } else {
                // ── Turned green: alert if red lasted ≥ 1 min ──
                if let start = redStartedAt, Date().timeIntervalSince(start) >= 60 {
                    playAlertSound()
                    postAlertNotification()
                }
                redStartedAt = nil
                stopBreathing()
                // Static green image
                statusItem.button?.image = LightRenderer.makeImage(on: true, color: .green)
            }
        }

        let cpuPct = Int(cpu * 100)
        statusItem.button?.toolTip = busy
            ? String(format: "High Load — CPU %d%%  GPU %d%%", cpuPct, gpu)
            : String(format: "Idle — CPU %d%%  GPU %d%%", cpuPct, gpu)

        stateMenuItem?.title = busy ? "State: 🔴 Busy" : "State: 🟢 Idle"
        cpuMenuItem?.title = "CPU: \(cpuPct)%"
        gpuMenuItem?.title = "GPU: \(gpu)%"
    }

    // MARK: - Breathing (red only)

    private func startBreathing() {
        breathStart = CACurrentMediaTime()
        breathPhase = 1.0
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.isBusy else { return }
            let elapsed = CACurrentMediaTime() - self.breathStart
            let cycleTime = elapsed.truncatingRemainder(dividingBy: self.breathCycleDuration)

            // Piecewise breathing: fade-in → hold-bright (2s) → fade-out
            let phase: CGFloat
            if cycleTime < self.fadeInDuration {
                let p = cycleTime / self.fadeInDuration
                phase = CGFloat((1.0 - cos(p * .pi)) / 2.0)
            } else if cycleTime < self.fadeInDuration + self.holdBrightDuration {
                phase = 1.0
            } else {
                let p = (cycleTime - self.fadeInDuration - self.holdBrightDuration) / self.fadeOutDuration
                phase = CGFloat((1.0 + cos(p * .pi)) / 2.0)
            }

            // Only redraw when phase changes — skips idle redraws during 2s hold-bright
            guard phase != self.lastDrawnPhase else { return }
            self.lastDrawnPhase = phase

            DispatchQueue.main.async {
                self.statusItem.button?.image = LightRenderer.makeImage(
                    on: true, color: .red, breath: phase)
            }
        }
    }

    private func stopBreathing() {
        breathTimer?.invalidate()
        breathTimer = nil
        breathPhase = 1.0
    }

    // MARK: - Alert Sound

    /// Play a loud, repeating alert — impossible to miss.
    /// Uses "Glass" system sound at max volume, repeated 3× with 0.4s gaps.
    private func playAlertSound() {
        guard let sound = NSSound(named: "Glass") else {
            // Fallback: system beep repeated 3×
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                    NSSound.beep()
                }
            }
            return
        }
        sound.volume = 1.0
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                sound.play()
            }
        }
    }

    /// Post a macOS notification banner for belt-and-suspenders alerting.
    private func postAlertNotification() {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "BusyLight"
        content.body = "High load has ended — CPU returned to normal"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "busylight-load-ended-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // fire immediately
        )
        center.add(request) { _ in }
    }

    // MARK: - Quit

    @objc private func quit() {
        monitor.stop()
        stopBreathing()
        NSApp.terminate(nil)
    }
}
