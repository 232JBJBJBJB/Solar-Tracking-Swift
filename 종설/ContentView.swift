import SwiftUI
import Combine

struct ContentView: View {
    @StateObject var bleManager = BluetoothManager()
    
    var batteryColor: Color {
        guard let adc = Int(bleManager.battValue) else { return .green }
        if adc >= 430 { return .green }
        else if adc >= 378 { return .yellow }
        else { return .red }
    }
    
    var body: some View {
        TabView {
            // --- 🏠 1. 홈 탭 ---
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // 블루투스 연결 버튼
                        Button(action: {
                            bleManager.toggleConnection()
                        }) {
                            HStack {
                                if bleManager.isScanning {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).padding(.trailing, 5)
                                    Text("스캔 취소하기")
                                } else {
                                    Image(systemName: bleManager.isConnected ? "link.badge.plus" : "wave.3.left")
                                    Text(bleManager.isConnected ? "연결 해제하기" : "블루투스 연결하기")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bleManager.isConnected ? Color.red.opacity(0.8) : (bleManager.isScanning ? Color.orange : Color.blue))
                            .foregroundColor(.white)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)
                        
                        // 시간 동기화 버튼 (이건 연결 안되면 막아둠)
                        Button(action: {
                            bleManager.syncCurrentTime()
                        }) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("하드웨어 시간 동기화")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bleManager.isConnected ? Color.purple : Color.gray.opacity(0.3))
                            .foregroundColor(bleManager.isConnected ? .white : .gray)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)
                        .disabled(!bleManager.isConnected)
                        
                        // 배터리/어댑터 카드
                        ZStack {
                            RoundedRectangle(cornerRadius: 25, style: .continuous)
                                .fill(bleManager.isAdapterActive ? Color.blue.opacity(0.1) : batteryColor.opacity(0.15))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Image(systemName: bleManager.isAdapterActive ? "powerplug.fill" : (batteryColor == .red ? "battery.25" : "battery.100.bolt"))
                                        .font(.system(size: 30))
                                        .foregroundColor(bleManager.isAdapterActive ? .blue : batteryColor)
                                    Spacer()
                                }
                                
                                Text(bleManager.isAdapterActive ? "어댑터 구동 중" : "배터리 구동 중")
                                    .font(.title2)
                                    .bold()
                                
                                Text("ADC 수치: \(bleManager.battValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding(25)
                        }
                        .frame(height: 160)
                        .padding(.horizontal)
                        
                        // 조도 센서
                        HStack(spacing: 15) {
                            SensorCard(title: "좌측 조도", value: bleManager.leftLDR, icon: "sun.min")
                            SensorCard(title: "우측 조도", value: bleManager.rightLDR, icon: "sun.max")
                        }
                        .padding(.horizontal)
                        
                        // 💡 추가된 부분: 전원 릴레이 수동 제어 섹션
                        VStack(alignment: .leading, spacing: 12) {
                            Text("전원 소스 강제 제어")
                                .font(.headline)
                                .padding(.leading, 5)
                            
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button(action: { bleManager.setRelayMode(mode: "AUTO") }) {
                                        Text("자동 (AUTO)")
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(Color.green.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                    
                                    Button(action: { bleManager.setRelayMode(mode: "OFF") }) {
                                        Text("모두 차단")
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(Color.gray.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                }
                                
                                HStack(spacing: 10) {
                                    Button(action: { bleManager.setRelayMode(mode: "IN1") }) {
                                        Text("배터리 (IN1)")
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(batteryColor.opacity(0.8)) // 배터리 상태 색상 반영
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                    
                                    Button(action: { bleManager.setRelayMode(mode: "IN2") }) {
                                        Text("어댑터 (IN2)")
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 15)
                                            .background(Color.blue.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 5)
                        .disabled(!bleManager.isConnected) // 연결 안 되면 회색으로 비활성화
                        .opacity(bleManager.isConnected ? 1.0 : 0.5)
                        
                    }
                    .padding(.top)
                    .padding(.bottom, 30)
                }
                .navigationTitle("Smart Tracker")
            }
            .tabItem { Label("홈", systemImage: "house.fill") }
            
            // --- ⏱️ 2. 제어 탭 ---
            ReservationView()
                .tabItem { Label("제어", systemImage: "slider.horizontal.3") }
            
            // --- 🛠 3. 디버그 탭 ---
            NavigationView {
                List(bleManager.debugLogs, id: \.self) { log in
                    Text("> \(log)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(log.contains("TX") ? .blue : (log.contains("RX") ? .green : .orange))
                }
                .navigationTitle("USART 디버그 모드")
            }
            .tabItem { Label("디버그", systemImage: "terminal.fill") }
        }
        .environmentObject(bleManager)
    }
}
