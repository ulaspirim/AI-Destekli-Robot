import 'robot_state.dart';

class RobotController {
  RobotState currentState = RobotState.exploring;

  void setState(RobotState newState) {
    if (currentState == newState) return;

    currentState = newState;
    print("🧠 Robot durumu değişti: $currentState");
  }

  bool get isExploring => currentState == RobotState.exploring;
  bool get isHumanDetected => currentState == RobotState.humanDetected;
  bool get isChatting => currentState == RobotState.chatting;
}
