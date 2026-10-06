import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/theme/app_icons.dart';

/// Bundled marks only: opening a plan never sends its domains to an icon service.
Widget blockingWebsiteIcon(String domain) {
  final host = domain.toLowerCase();
  String? mark;
  for (final entry in _marks.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      mark = entry.value;
      break;
    }
  }
  if (mark == null) return const Icon(AppIcons.publicOutlined, size: 24);
  return SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">$mark</svg>',
    width: 24,
    height: 24,
    excludeFromSemantics: true,
  );
}

const _marks = {
  'instagram.com':
      '<defs><linearGradient id="g" x2="1" y2="1"><stop stop-color="#a23bcd"/><stop offset="1" stop-color="#f3a34b"/></linearGradient></defs><rect width="24" height="24" rx="6" fill="url(#g)"/><rect x="5" y="5" width="14" height="14" rx="4" fill="none" stroke="white" stroke-width="1.8"/><circle cx="12" cy="12" r="3.5" fill="none" stroke="white" stroke-width="1.8"/><circle cx="17" cy="7" r="1" fill="white"/>',
  'youtube.com':
      '<rect x="1" y="4" width="22" height="16" rx="5" fill="#ff0033"/><path d="M10 8L17 12L10 16Z" fill="white"/>',
  'x.com':
      '<rect width="24" height="24" rx="5" fill="#141414"/><path d="M6 5L18 19M18 5L6 19" stroke="white" stroke-width="2"/>',
  'facebook.com':
      '<rect width="24" height="24" rx="5" fill="#1877f2"/><path d="M14 22V14H17L18 10H14V8Q14 6 18 6V2Q10 1 10 8V10H7V14H10V22Z" fill="white"/>',
  'reddit.com':
      '<circle cx="12" cy="12" r="12" fill="#ff4500"/><ellipse cx="12" cy="14" rx="8" ry="5" fill="white"/><path d="M12 9L13 5L18 6" stroke="white" fill="none"/><circle cx="18" cy="6" r="2" fill="white"/><circle cx="9" cy="13" r="1.2" fill="#ff4500"/><circle cx="15" cy="13" r="1.2" fill="#ff4500"/><path d="M9 16Q12 18 15 16" stroke="#ff4500" fill="none"/>',
  'twitch.tv':
      '<rect width="24" height="24" rx="5" fill="#9146ff"/><path d="M5 4H20V15L15 20H10L6 23V18H4V6Z" fill="white"/><path d="M9 7H17V14L14 17H9Z" fill="#9146ff"/><path d="M11 8V12M15 8V12" stroke="white"/>',
};
