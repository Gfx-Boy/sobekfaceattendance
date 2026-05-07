import 'package:flutter/material.dart';

/// Full-screen semi-transparent overlay that blocks user input while a
/// background task (e.g. an upload) is running. Used to satisfy the
/// "freeze the UI during uploads" requirement so employees can't tap twice
/// or navigate away before the network round-trip finishes.
class BlockingOverlay extends StatelessWidget {
  final Widget child;
  final bool blocking;
  final String? message;

  const BlockingOverlay({
    super.key,
    required this.child,
    required this.blocking,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !blocking,
      child: Stack(children: [
        child,
        if (blocking)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: ColoredBox(
                color: const Color(0x66000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          message!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
