import SwiftUI

struct SensorCard: View {
    var title: String
    var value: String
    var icon: String
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
            
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.orange)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.title3)
                    .bold()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 120)
    }
}
