import SwiftUI
import Combine

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ReservationView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    @State private var turnOnTime  = Date()
    @State private var turnOffTime = Date()
    @State private var currentTime = Date()

    let timer   = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 상단 시계
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black)
                    VStack(spacing: 5) {
                        Text("Current Time").font(.subheadline).foregroundColor(.gray)
                        Text(timeString(from: currentTime))
                            .font(.system(size: 45, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .frame(height: 120).padding()
                .onReceive(timer) { currentTime = $0 }

                Form {
                    // 1. 모드 선택
                    Section(header: Text("제어 모드 (Mode)")) {
                        Toggle(isOn: Binding(
                            get: { bleManager.isAutoMode },
                            set: { newValue in
                                bleManager.isAutoMode = newValue
                                bleManager.sendCommand(newValue ? "MODE:AUTO\n" : "MODE:MANUAL\n")

                                // [버그1] MANUAL 전환 시 현재 LED 상태를 펌웨어에 재전송.
                                // 수정된 펌웨어는 MODE:MANUAL 수신 시 relay_request = 0으로
                                // 초기화하므로, 앱의 현재 LED 의도를 즉시 다시 알려야
                                // 앱 표시와 하드웨어 상태가 일치함.
                                // 0.1초 딜레이: HM-10 BLE 연속 패킷이 붙어서 오면
                                // 펌웨어 ISR의 \n 파싱이 두 번째 명령을 씹을 수 있어
                                // 약간의 간격을 줌.
                                if !newValue {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        bleManager.updateLEDTarget()
                                    }
                                }
                            }
                        )) {
                            HStack {
                                Image(systemName: bleManager.isAutoMode ? "clock.fill" : "hand.tap.fill")
                                    .foregroundColor(bleManager.isAutoMode ? .green : .orange)
                                Text(bleManager.isAutoMode ? "AUTO (예약 시간 작동)" : "MANUAL (터치 즉시 작동)")
                                    .fontWeight(.bold)
                            }
                        }
                        .padding(.vertical, 5)
                    }

                    // 2. LED 통합 제어
                    Section(header: Text("점등할 LED 선택 (Sync with Hardware)")) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(0..<4, id: \.self) { index in
                                Button(action: {
                                    bleManager.toggleLED(index: index)
                                }) {
                                    HStack {
                                        Image(systemName: bleManager.ledStates[index] ? "lightbulb.fill" : "lightbulb")
                                        Text("LED \(index)").fontWeight(.bold)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(bleManager.ledStates[index] ? Color.yellow : Color.black)
                                    .foregroundColor(bleManager.ledStates[index] ? .black : .white)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 5)
                    }

                    // 3. 타이머 예약
                    Section(header: Text("타이머 설정 (Timer)")) {
                        DatePicker("점등 (ON)",  selection: $turnOnTime,  displayedComponents: .hourAndMinute)
                        DatePicker("소등 (OFF)", selection: $turnOffTime, displayedComponents: .hourAndMinute)

                        Button(action: sendReservation) {
                            HStack { Spacer(); Text("예약 시간 전송하기").bold(); Spacer() }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationTitle("기기 제어")
        }
    }

    func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    func sendReservation() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        bleManager.sendCommand("RES:\(formatter.string(from: turnOnTime)),\(formatter.string(from: turnOffTime))\n")
    }
}
