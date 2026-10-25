import AVFoundation
import SwiftUI

// MARK: - VoiceSetupView

struct VoiceSetupView: View {
    @ObservedObject var service = AudioAlertService.shared
    @Binding var isPresented: Bool

    @State private var testDone = false
    @State private var readyDone = false
    @State private var speakPulse = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Icône ────────────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 90, height: 90)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Color.orange)
                        .scaleEffect(speakPulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: speakPulse)
                }
                .padding(.top, 32)

                Text("Voix des alertes")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.top, 16)
                Text("Choisissez la voix qui annoncera les radars lors de vos trajets.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)

                // ── Liste des voix ───────────────────────────────────────────
                List(service.availableVoices, id: \.identifier) { voice in
                    Button {
                        service.selectVoice(voice)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(service.selectedVoice?.identifier == voice.identifier
                                          ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08))
                                    .frame(width: 36, height: 36)
                                Image(systemName: service.selectedVoice?.identifier == voice.identifier
                                      ? "checkmark.circle.fill" : "person.wave.2")
                                    .foregroundStyle(service.selectedVoice?.identifier == voice.identifier
                                                     ? Color.orange : .secondary)
                                    .font(.system(size: 16))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                    .font(.system(size: 15, weight: .medium))
                                HStack(spacing: 6) {
                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if voice.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue {
                                        Text("HD")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.orange)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(maxHeight: 280)

                Divider().padding(.horizontal, 20)

                // ── Boutons ──────────────────────────────────────────────────
                VStack(spacing: 12) {
                    Button {
                        testDone = false
                        readyDone = false
                        service.testAlert()
                        // Après l'alerte test, annoncer "prête" automatiquement
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            testDone = true
                            service.announceReady()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                readyDone = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: service.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            Text(testDone ? "Rejouer le test" : "Tester la voix")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isSpeaking)

                    Button {
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: readyDone ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            Text(readyDone ? "C'est parfait, allons-y !" : "Continuer sans tester")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(readyDone ? Color.green : Color.primary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(readyDone ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.3), value: readyDone)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .navigationBarHidden(true)
        }
        .onChange(of: service.isSpeaking) { _, speaking in
            speakPulse = speaking
        }
    }
}
