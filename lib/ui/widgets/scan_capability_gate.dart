import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/scan/bloc/scan_capability_cubit.dart';

/// Shows [child] only on devices that can actually scan.
///
/// Scanning needs ARCore, which Google certifies per device; on an
/// uncertified handset the flow can never start. Rather than repeat that
/// check at every scan entry point (Home card, Explore CTA, and whatever M3
/// adds), they all wrap in this.
///
/// Renders nothing at all when unavailable — not a disabled control. A
/// disabled button still lands in the screen-reader focus order and still
/// invites a tap, which for a permanent hardware limitation is a dead end
/// dressed up as an option.
class ScanCapabilityGate extends StatelessWidget {
  const ScanCapabilityGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScanCapabilityCubit, ScanCapability>(
      builder: (context, capability) => switch (capability) {
        // Hidden while checking too, so an entry point never appears and then
        // disappears under a finger already reaching for it.
        ScanCapability.checking => const SizedBox.shrink(),
        ScanCapability.unavailable => const SizedBox.shrink(),
        ScanCapability.available => child,
      },
    );
  }
}
