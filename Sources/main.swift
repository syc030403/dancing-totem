import AppKit
import ImageIO
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - 설정

/// 메뉴바에 그릴 그림 높이(pt)
let iconHeight: CGFloat = 16
/// 그림이 너무 넓어지지 않도록 하는 최대 너비(pt)
let maxIconWidth: CGFloat = 64
/// CPU 0%일 때 재생 배속 (GIF 원래 속도 대비)
let minSpeed = 0.25
/// CPU 100%일 때 재생 배속
let maxSpeed = 3.0
/// CPU 측정 주기(초)
let cpuSampleInterval = 1.0

// MARK: - GIF 로딩

struct Animation {
    /// 메뉴바 크기로 미리 줄여 둔 프레임. 내용이 같은 프레임은 같은 객체를 공유한다.
    var frames: [CGImage]
    /// 각 프레임이 끝나는 시각(초, 누적). 마지막 값이 한 바퀴 길이다.
    var endTimes: [Double]
    /// 메뉴바에서 차지하는 크기(pt)
    var size: NSSize

    var duration: Double { endTimes.last ?? 0 }

    /// 한 바퀴 안의 시각 t에 보여줄 프레임 번호
    func frameIndex(at time: Double) -> Int {
        var low = 0, high = endTimes.count - 1
        while low < high {
            let mid = (low + high) / 2
            if endTimes[mid] > time { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

private func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}

private func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
    let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
    let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
        ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
    return delay < 0.011 ? 0.1 : delay // 0에 가까운 값은 브라우저처럼 0.1초로 본다
}

/// GIF(또는 정지 이미지)를 읽어 메뉴바용 애니메이션으로 만든다.
func loadAnimation(from url: URL) -> Animation? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0, let first = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let canvas = makeContext(width: first.width, height: first.height),
          let canvasData = canvas.data else { return nil }

    let width = first.width, height = first.height
    let byteCount = width * height * 4
    let pixels = canvasData.bindMemory(to: UInt8.self, capacity: byteCount)
    let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

    /// 프레임을 캔버스에 그리고, 단색 불투명 배경이면 투명하게 뺀다.
    func render(_ index: Int) -> Bool {
        guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { return false }
        canvas.clear(fullRect)
        canvas.draw(frame, in: fullRect)

        // 네 모서리가 모두 같은 불투명 색일 때만 그 색을 배경으로 본다(사진 GIF는 건드리지 않는다).
        let corners = [0, (width - 1) * 4, (height - 1) * width * 4, byteCount - 4]
        let (r, g, b) = (pixels[0], pixels[1], pixels[2])
        let solidBackground = corners.allSatisfy {
            pixels[$0 + 3] == 255 && pixels[$0] == r && pixels[$0 + 1] == g && pixels[$0 + 2] == b
        }
        if solidBackground {
            for offset in stride(from: 0, to: byteCount, by: 4) {
                if abs(Int(pixels[offset]) - Int(r)) < 12, abs(Int(pixels[offset + 1]) - Int(g)) < 12,
                   abs(Int(pixels[offset + 2]) - Int(b)) < 12 {
                    pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
                }
            }
        }
        return true
    }

    // 1차: 모든 프레임에서 그림이 차지하는 영역(합집합)을 구해 투명 여백을 잘라낸다.
    var minX = width, minY = height, maxX = -1, maxY = -1
    for index in 0..<count where render(index) {
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)

    // 2차: 잘라낸 프레임을 메뉴바 크기(레티나 2배)로 줄인다.
    var scale = iconHeight / crop.height
    if crop.width * scale > maxIconWidth { scale = maxIconWidth / crop.width }
    let size = NSSize(width: max((crop.width * scale).rounded(), 1), height: max((crop.height * scale).rounded(), 1))
    let pixelWidth = Int(size.width) * 2, pixelHeight = Int(size.height) * 2
    guard let small = makeContext(width: pixelWidth, height: pixelHeight), let smallData = small.data else { return nil }
    // 정수 배율로 줄어드는 픽셀 아트는 경계를 뭉개지 않는다.
    let pixelArt = Int(crop.width) % pixelWidth == 0 && Int(crop.height) % pixelHeight == 0
    small.interpolationQuality = pixelArt ? .none : .high
    let smallRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)

    var frames: [CGImage] = [], endTimes: [Double] = []
    var cache: [Data: CGImage] = [:]
    var elapsed = 0.0
    for index in 0..<count where render(index) {
        guard let cropped = canvas.makeImage()?.cropping(to: crop) else { continue }
        small.clear(smallRect)
        small.draw(cropped, in: smallRect)
        let key = Data(bytes: smallData, count: pixelWidth * pixelHeight * 4)
        guard let image = cache[key] ?? small.makeImage() else { continue }
        cache[key] = image
        elapsed += frameDelay(source, index)
        frames.append(image)
        endTimes.append(elapsed)
    }
    return frames.isEmpty ? nil : Animation(frames: frames, endTimes: endTimes, size: size)
}

// MARK: - CPU 측정

/// 전체 코어 기준 CPU 사용률(0...1). 직전 호출 이후의 평균값이다.
final class CPUMonitor {
    private var previous: (busy: UInt64, total: UInt64)?

    func sample() -> Double? {
        var info = host_cpu_load_info()
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let current = (busy: user + system + nice, total: user + system + nice + idle)
        defer { previous = current }

        guard let previous, current.total > previous.total else { return nil }
        let usage = Double(current.busy - previous.busy) / Double(current.total - previous.total)
        return min(max(usage, 0), 1)
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = CPUMonitor()
    private var animation: Animation?
    /// 버튼 이미지를 매번 갈아 끼우면 메뉴바 전체가 다시 그려져 무겁다.
    /// 그래서 자리만 잡는 빈 이미지를 넣어 두고, 그 위에 얹은 레이어의 내용만 바꾼다.
    private let spriteLayer = CALayer()

    private var cpuUsage = 0.0   // 최근 측정값
    private var speed = minSpeed // 현재 재생 배속
    private var playhead = 0.0   // 한 바퀴 안에서의 재생 위치(초)
    private var lastTick = CACurrentMediaTime()

    private let cpuMenuItem = NSMenuItem(title: "CPU: 측정 중…", action: nil, keyEquivalent: "")
    private let percentMenuItem = NSMenuItem(title: "메뉴바에 CPU % 표시", action: #selector(togglePercent), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")

    private var showPercent: Bool {
        get { UserDefaults.standard.bool(forKey: "showPercent") }
        set { UserDefaults.standard.set(newValue, forKey: "showPercent") }
    }

    /// 사용자가 고른 GIF를 복사해 두는 위치
    private var userGIFURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Dancing Totem/animation.gif")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.wantsLayer = true
        spriteLayer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        button.layer?.addSublayer(spriteLayer)

        let menu = NSMenu()
        menu.addItem(cpuMenuItem)
        menu.addItem(.separator())
        let chooseItem = NSMenuItem(title: "GIF 선택…", action: #selector(chooseGIF), keyEquivalent: "o")
        chooseItem.target = self
        percentMenuItem.target = self
        loginMenuItem.target = self
        menu.addItem(chooseItem)
        menu.addItem(percentMenuItem)
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // 사용자가 고른 GIF가 우선이고, 없으면 앱에 들어 있는 GIF(있을 때만)를 쓴다.
        let candidates = [userGIFURL, Bundle.main.url(forResource: "dancer", withExtension: "gif")].compactMap { $0 }
        setAnimation(candidates.lazy.compactMap { loadAnimation(from: $0) }.first)

        _ = monitor.sample()
        // 메뉴가 열려 있을 때도 움직이도록 common 모드에 등록한다.
        let cpuTimer = Timer(timeInterval: cpuSampleInterval, repeats: true) { [weak self] _ in self?.updateCPU() }
        let frameTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        frameTimer.tolerance = 0.005
        RunLoop.main.add(cpuTimer, forMode: .common)
        RunLoop.main.add(frameTimer, forMode: .common)
    }

    private func setAnimation(_ newAnimation: Animation?) {
        animation = newAnimation
        playhead = 0
        spriteLayer.contents = nil
        // 자리만 차지하는 투명 이미지. 실제 그림은 spriteLayer가 그린다.
        statusItem.button?.image = newAnimation.map { NSImage(size: $0.size) }
        refreshTitle()
        tick()
    }

    private func refreshTitle() {
        percentMenuItem.state = showPercent ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let percent = String(format: "%3d%%", Int((cpuUsage * 100).rounded()))
        if showPercent {
            statusItem.button?.title = percent
        } else {
            // GIF가 아직 없으면 메뉴를 열 수 있도록 글자를 대신 보여준다.
            statusItem.button?.title = animation == nil ? "GIF 선택" : ""
        }
    }

    private func updateCPU() {
        guard let usage = monitor.sample() else { return }
        cpuUsage = usage
        cpuMenuItem.title = "CPU: \(Int((usage * 100).rounded()))%"
        refreshTitle()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let delta = min(now - lastTick, 0.25)
        lastTick = now
        guard let animation, animation.duration > 0 else { return }

        // 속도가 갑자기 튀지 않도록 목표 속도로 부드럽게 따라간다.
        let target = minSpeed + (maxSpeed - minSpeed) * cpuUsage
        speed += (target - speed) * min(delta * 2.5, 1)
        playhead = (playhead + speed * delta).truncatingRemainder(dividingBy: animation.duration)

        let frame = animation.frames[animation.frameIndex(at: playhead)]
        if spriteLayer.contents as AnyObject? !== frame {
            if let button = statusItem.button, let cell = button.cell as? NSButtonCell {
                let rect = cell.imageRect(forBounds: button.bounds)
                if spriteLayer.frame != rect { spriteLayer.frame = rect }
            }
            spriteLayer.contents = frame
        }
    }

    @objc private func chooseGIF() {
        let panel = NSOpenPanel()
        panel.title = "메뉴바에서 재생할 GIF 선택"
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let loaded = loadAnimation(from: url) else {
            showAlert("이 파일은 재생할 수 없습니다", "GIF 파일인지 확인해 주세요.")
            return
        }
        do {
            let destination = userGIFURL
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            showAlert("GIF를 저장하지 못했습니다", "이번 실행에서만 적용됩니다. \(error.localizedDescription)")
        }
        setAnimation(loaded)
    }

    @objc private func togglePercent() {
        showPercent.toggle()
        refreshTitle()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("자동 실행 설정을 바꾸지 못했습니다", error.localizedDescription)
        }
        refreshTitle()
    }

    private func showAlert(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// 로딩 결과만 확인하는 옵션: --check <gif>
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check" {
    if let animation = loadAnimation(from: URL(fileURLWithPath: CommandLine.arguments[2])) {
        print("frames: \(animation.frames.count), unique: \(Set(animation.frames.map { ObjectIdentifier($0) }).count),",
              "size: \(Int(animation.size.width))x\(Int(animation.size.height))pt, loop: \(animation.duration)s")
        exit(0)
    }
    print("불러오기 실패")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
