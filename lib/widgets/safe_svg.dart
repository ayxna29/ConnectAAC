import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Safely load an SVG asset by reading it via rootBundle first.
/// If loading fails, shows a placeholder icon instead of throwing.
class SafeSvg extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;
  final double? height;

  const SafeSvg({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          try {
            return SvgPicture.string(snapshot.data!, fit: fit, height: height);
          } catch (e) {
            // Fallthrough to placeholder
          }
        }
        if (snapshot.hasError) {
          // ignore: avoid_print
          print('SafeSvg load error for $assetPath: ${snapshot.error}');
        }
        return Container(
          height: height ?? 120,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.black26),
          ),
        );
      },
    );
  }
}
