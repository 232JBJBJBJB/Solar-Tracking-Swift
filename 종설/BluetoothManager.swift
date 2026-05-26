import Foundation
import CoreBluetooth
import UserNotifications
import Combine

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var battValue = "0"
    @Published var leftLDR = "0"
    @Published var rightLDR = "0"
    @Published var isAdapterActive = false

    @Published var isAutoMode: Bool = false
    @Published var ledStates: [Bool] = [false, false, false, false]
    @Published var debugLogs: [String] = []

    var centralManager: CBCentralManager!
    var hm10Peripheral: CBPeripheral?
    var txCharacteristic: CBCharacteristic?

    private var rxBuffer = ""

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        requestNotificationPermission()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // LED 상태 통합 전송
    func updateLEDTarget() {
        let bits = ledStates.map { $0 ? "1" : "0" }.joined()
        sendCommand("LED:\(bits)\n")
    }

    // 개별 LED 토글
    func toggleLED(index: Int) {
        ledStates[index].toggle()
        updateLEDTarget()
    }

    // 서보 명령
    func moveServo(position: String) {
        sendCommand("SRV:\(position)\n")
    }

    // 릴레이 수동 모드 명령
    func setRelayMode(mode: String) {
        sendCommand("RLY:\(mode)\n")
    }

    // 블루투스 상태 확인
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("블루투스 사용 가능")
        } else {
            print("블루투스가 꺼져 있거나 권한이 없습니다.")
        }
    }

    // 연결/해제/스캔취소 통합
    func toggleConnection() {
        if isConnected        { disconnect() }
        else if isScanning    { stopScanning() }
        else                  { startScanning() }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.async { [weak self] in
            self?.debugLogs.insert("블루투스 스캔 시작...", at: 0)
        }
    }

    func stopScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.debugLogs.insert("블루투스 스캔 취소됨", at: 0)
        }
    }

    func disconnect() {
        if let peripheral = hm10Peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // HM-10 필터링
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name, name.contains("HM-10") || name.contains("HMSoft") {
            hm10Peripheral = peripheral
            hm10Peripheral?.delegate = self
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.isScanning  = false
            self?.debugLogs.insert("HM-10 연결 성공!", at: 0)
        }
        peripheral.discoverServices([CBUUID(string: "FFE0")])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected  = false
            self?.hm10Peripheral   = nil
            self?.txCharacteristic = nil
            self?.debugLogs.insert("블루투스 연결 끊김", at: 0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([CBUUID(string: "FFE1")], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: "FFE1") {
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    // ── 수신 파싱 ────────────────────────────────────────────
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let received = String(data: data, encoding: .utf8) else { return }

        rxBuffer += received

        while let range = rxBuffer.range(of: "\n") {
            let line = String(rxBuffer[..<range.lowerBound])
            rxBuffer.removeSubrange(rxBuffer.startIndex...range.upperBound)

            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.debugLogs.insert("RX: \(clean)", at: 0)

                let components = clean.split(separator: ",")
                for comp in components {
                    let pair = comp.split(separator: ":")
                    guard pair.count >= 2 else { continue }

                    let key   = String(pair[0])
                    let value = pair[1...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)

                    switch key {
                    case "BAT": self.battValue      = value
                    case "L":   self.leftLDR        = value
                    case "R":   self.rightLDR       = value
                    case "ADP": self.isAdapterActive = (value == "1")

                    case "LED":
                        if value.count >= 4 {
                            let chars = Array(value)
                            self.ledStates[0] = (chars[0] == "1")
                            self.ledStates[1] = (chars[1] == "1")
                            self.ledStates[2] = (chars[2] == "1")
                            self.ledStates[3] = (chars[3] == "1")
                        }

                    // [버그1] 펌웨어가 매초 MOD 값을 송신하므로
                    // 앱을 껐다 켜거나 연결이 끊겼다 재연결되어도
                    // 펌웨어 실제 모드로 자동 동기화됨.
                    // 기존에는 앱 재시작 시 isAutoMode가 false로 초기화되어
                    // 펌웨어가 AUTO 상태여도 앱은 MANUAL로 표시했고,
                    // 그 결과 릴레이 제어 분기가 엇갈려 명령이 무시됐음.
                    case "MOD":
                        self.isAutoMode = (value == "1")

                    default: break
                    }
                }

                if self.debugLogs.count > 50 {
                    self.debugLogs.removeLast()
                }
            }
        }
    }

    // ── 명령 송신 ────────────────────────────────────────────
    func sendCommand(_ command: String) {
        guard let data = command.data(using: .utf8),
              let char = txCharacteristic else { return }
        hm10Peripheral?.writeValue(data, for: char, type: .withoutResponse)

        DispatchQueue.main.async { [weak self] in
            if !command.contains("SYNC") {
                self?.debugLogs.insert("TX: \(command.trimmingCharacters(in: .newlines))", at: 0)
            }
        }
    }

    // ── 시간 동기화 ──────────────────────────────────────────
    func syncCurrentTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        let command = "SYNC:\(formatter.string(from: Date()))\n"
        sendCommand(command)
        DispatchQueue.main.async { [weak self] in
            self?.debugLogs.insert("TX (시간 전송): \(command.trimmingCharacters(in: .newlines))", at: 0)
        }
    }
}
