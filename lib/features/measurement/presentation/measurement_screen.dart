import 'package:flutter/material.dart';

/// Main measurement screen for acoustic distance measurement
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  // TODO: Integrate with MeasurementController for state management

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),

        title: const Text('Measure'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Measurement Screen'),
            // TODO: Add radar visualization widget
            // TODO: Add distance display
            // TODO: Add start/stop measurement button
          ],
        ),
      ),
    );
  }
}
