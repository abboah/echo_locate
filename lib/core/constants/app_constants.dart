/// Application-wide constants for EchoLocate acoustic sonar app
class AppConstants {
  AppConstants._();

  // Acoustic Chirp Parameters
  static const double chirpFrequencyStart = 16000.0; // Hz (ultrasonic)
  static const double chirpFrequencyEnd = 20000.0; // Hz (ultrasonic)
  static const int chirpDurationMs = 20; // milliseconds

  // Physics Constants
  static const double speedOfSound = 343.0; // m/s at room temperature

  // Measurement Constraints
  static const double maxMeasurementDistance = 10.0; // meters
  static const double minMeasurementDistance = 0.5; // meters

  // Audio Configuration
  static const int sampleRate = 44100; // Hz
}
