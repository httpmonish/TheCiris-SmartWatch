import 'dart:async';

enum SosState {
  idle,
  countdown15s,
  escalatedToDispatch,
  dismissedByWearer,
}

class SosEscalationManager {
  SosState state = SosState.idle;
  int remainingSeconds = 15;
  Timer? _timer;
  String triggerReason = '';

  final void Function(int secondsRemaining) onTick;
  final void Function(String reason) onDispatchEmergency;
  final void Function(List<int> vibrationPattern) onHapticRequest;

  SosEscalationManager({
    required this.onTick,
    required this.onDispatchEmergency,
    required this.onHapticRequest,
  });

  /// Trigger emergency countdown (15 seconds for automated risk/fall, 10 seconds for manual button)
  void startEscalation({required String reason, bool isManualPanic = false}) {
    if (state == SosState.countdown15s || state == SosState.escalatedToDispatch) {
      return; // Already in progress
    }

    triggerReason = reason;
    state = SosState.countdown15s;
    remainingSeconds = isManualPanic ? 10 : 15;

    // Pulse haptic pattern: [delay_ms, vibrate_ms, wait_ms, vibrate_ms]
    onHapticRequest([0, 400, 150, 400]);
    onTick(remainingSeconds);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remainingSeconds--;
      onTick(remainingSeconds);

      // Warning buzzer pattern on every tick
      onHapticRequest([0, 100]);

      if (remainingSeconds <= 0) {
        timer.cancel();
        state = SosState.escalatedToDispatch;
        onDispatchEmergency(triggerReason);
      }
    });
  }

  /// Wearer explicitly presses "I'M OK / DISMISS" on watch or app
  void dismissByWearer() {
    _timer?.cancel();
    state = SosState.dismissedByWearer;
    remainingSeconds = 0;
    onTick(0);
  }

  void reset() {
    _timer?.cancel();
    state = SosState.idle;
    remainingSeconds = 15;
    triggerReason = '';
  }

  void dispose() {
    _timer?.cancel();
  }
}
