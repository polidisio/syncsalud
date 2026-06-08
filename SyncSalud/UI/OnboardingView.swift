import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @Environment(HealthKitService.self) private var healthService

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage
                    .tag(0)

                healthKitPage
                    .tag(1)

                iCloudPage
                    .tag(2)

                completionPage
                    .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut, value: currentPage)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("onboarding.welcome.title")
                    .font(.largeTitle.bold())

                Text("onboarding.welcome.subtitle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            pageIndicator(total: 4, current: 0)

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("onboarding.welcome.button")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var healthKitPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)

            VStack(spacing: 12) {
                Text("onboarding.health.title")
                    .font(.largeTitle.bold())

                Text("onboarding.health.description")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("onboarding.health.reassurance")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            Spacer()

            pageIndicator(total: 4, current: 1)

            Button {
                Task {
                    await healthService.requestAuthorization()
                    withAnimation { currentPage = 2 }
                }
            } label: {
                Text("onboarding.health.grant")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Button {
                withAnimation { currentPage = 2 }
            } label: {
                Text("onboarding.health.skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
    }

    private var iCloudPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "icloud.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("onboarding.icloud.title")
                    .font(.largeTitle.bold())

                Text("onboarding.icloud.description")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("onboarding.icloud.hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            pageIndicator(total: 4, current: 2)

            Button {
                withAnimation { currentPage = 3 }
            } label: {
                Text("onboarding.icloud.understood")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var completionPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("onboarding.complete.title")
                    .font(.largeTitle.bold())

                Text("onboarding.complete.subtitle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            pageIndicator(total: 4, current: 3)

            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("onboarding.complete.button")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    private func pageIndicator(total: Int, current: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(HealthKitService())
}
