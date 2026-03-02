/// Time-of-Flight (ToF) calculator for distance measurement
class ToFCalculator {
  /// Calculates distance from time-of-flight
  ///
  /// [peakIndex] - Sample index where the correlation peak occurs
  /// [sampleRate] - Audio sample rate in Hz
  /// [speedOfSound] - Speed of sound in m/s (default 343 m/s at room temp)
  ///
  /// Returns distance in meters
  ///
  /// Formula: distance = (peakIndex / sampleRate) * speedOfSound / 2
  /// The divide-by-2 accounts for the round trip (signal travels to object and back)
  double calculateDistance({
    required int peakIndex,
    required int sampleRate,
    required double speedOfSound,
  }) {
    // Time of flight = peakIndex / sampleRate (in seconds)
    // Distance = (timeOfFlight * speedOfSound) / 2 (round trip)
    final timeOfFlight = peakIndex / sampleRate;
    final distance = (timeOfFlight * speedOfSound) / 2;

    return distance;
  }

  /// Converts time delay in seconds to distance
  double timeToDistance(double timeSeconds, double speedOfSound) {
    // Round trip: divide by 2
    return (timeSeconds * speedOfSound) / 2;
  }

  /// Converts distance to expected time delay
  double distanceToTime(double distanceMeters, double speedOfSound) {
    // Round trip: multiply by 2
    return (distanceMeters * 2) / speedOfSound;
  }

  /// Validates if the calculated distance is within acceptable range
  bool isValidDistance(
    double distance,
    double minDistance,
    double maxDistance,
  ) {
    return distance >= minDistance && distance <= maxDistance;
  }
}
