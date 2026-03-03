import 'package:echo_locate/core/constants/app_constants.dart';

/// Time-of-Flight (ToF) calculator for distance measurement
class ToFCalculator {
  /// Calculates distance from time-of-flight correlation data
  ///
  /// [correlation] - Cross-correlation values at each lag
  /// [sampleRate] - Audio sample rate in Hz
  /// [speedOfSound] - Speed of sound in m/s
  ///
  /// Returns distance in meters, or -1.0 if measurement failed
  ///
  /// Steps:
  /// 1. Find the index of the peak value in the correlation list
  /// 2. Apply a minimum threshold — ignore peaks below 10% of the max value (noise gate)
  /// 3. Calculate: distance = (peakIndex / sampleRate) * speedOfSound / 2
  /// 4. Clamp result between MIN_MEASUREMENT_DISTANCE and MAX_MEASUREMENT_DISTANCE
  /// 5. Return -1.0 if no valid peak found (measurement failed)
  double calculateDistance(
    List<double> correlation,
    int sampleRate,
    double speedOfSound,
  ) {
    if (correlation.isEmpty) {
      return -1.0;
    }

    // Find the index of the peak value in the correlation list
    // The peak represents the strongest match with the transmitted chirp
    double maxVal = double.negativeInfinity;
    int peakIndex = -1;

    for (int i = 0; i < correlation.length; i++) {
      if (correlation[i] > maxVal) {
        maxVal = correlation[i];
        peakIndex = i;
      }
    }

    if (peakIndex == -1) {
      return -1.0;
    }

    // Apply a minimum threshold — ignore peaks below 10% of the max value (noise gate)
    // This filters out weak signals that are likely noise
    final noiseThreshold = maxVal * 0.1;
    if (maxVal < noiseThreshold) {
      return -1.0;
    }

    // Attempt to refine peak position using parabolic interpolation for sub-sample accuracy
    // This gives us a more precise time-of-flight measurement
    final refinedPeakIndex =
        refineWithParabolicInterpolation(correlation, peakIndex) ??
        peakIndex.toDouble();

    // Calculate time of flight = peakIndex / sampleRate
    // This is the time delay between transmission and reception
    final timeOfFlight = refinedPeakIndex / sampleRate;

    // Calculate distance = (timeOfFlight * speedOfSound) / 2
    // The divide-by-2 accounts for the round trip (signal travels to object and back)
    final distance = (timeOfFlight * speedOfSound) / 2.0;

    // Clamp result between MIN_MEASUREMENT_DISTANCE and MAX_MEASUREMENT_DISTANCE
    // This validates that the measurement is within acceptable physical bounds
    final clampedDistance = distance.clamp(
      AppConstants.minMeasurementDistance,
      AppConstants.maxMeasurementDistance,
    );

    // Return the clamped distance
    return clampedDistance;
  }

  /// Refines peak position using 3-point parabolic interpolation
  ///
  /// Uses parabolic interpolation around the peak for sub-sample accuracy.
  /// This improves time-of-flight measurement precision.
  ///
  /// [correlation] - Cross-correlation values
  /// [peakIndex] - Index of the detected peak
  ///
  /// Returns refined peak index as a double, or null if at edges
  double? refineWithParabolicInterpolation(
    List<double> correlation,
    int peakIndex,
  ) {
    // Return null if peakIndex is 0 or last index (can't interpolate at edges)
    // We need samples on both sides of the peak for 3-point interpolation
    if (peakIndex <= 0 || peakIndex >= correlation.length - 1) {
      return null;
    }

    // Extract the three correlation values around the peak
    // corr[peak-1], corr[peak], corr[peak+1]
    final y0 = correlation[peakIndex - 1];
    final y1 = correlation[peakIndex];
    final y2 = correlation[peakIndex + 1];

    // Use 3-point parabolic interpolation to find sub-sample offset
    // Formula: offset = 0.5 * (y0 - y2) / (y0 - 2*y1 + y2)
    // This fits a parabola through the three points and finds the vertex
    final denominator = y0 - 2.0 * y1 + y2;

    // Avoid division by zero
    if (denominator.abs() < 1e-10) {
      return null;
    }

    // Calculate the offset from the discrete peak index
    // Negative offset means peak is before peakIndex, positive means after
    final offset = 0.5 * (y0 - y2) / denominator;

    // Return the refined peak index: peakIndex + offset
    // This is a floating-point index that may be between samples
    return peakIndex + offset;
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
