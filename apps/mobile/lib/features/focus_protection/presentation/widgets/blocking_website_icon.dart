import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/theme/app_icons.dart';
import 'blocking_website_marks.dart';

/// Bundled brand paths only; no user's domain is sent to an icon service.
Widget blockingWebsiteIcon(String domain) {
  final host = domain.toLowerCase();
  String? mark;
  for (final entry in blockingWebsiteMarks.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      mark = entry.value;
      break;
    }
  }
  if (mark == null) return const Icon(AppIcons.publicOutlined, size: 24);
  // The neutral backing preserves contrast without recoloring brand geometry.
  return SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<rect width="24" height="24" rx="5" fill="#fff"/>'
    '<g transform="translate(2 2) scale(.833333)">$mark</g></svg>',
    width: 24,
    height: 24,
    excludeFromSemantics: true,
  );
}
