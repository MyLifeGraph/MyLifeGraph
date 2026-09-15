import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Transient shell gesture intent, consumed only by an already visible Planner.
/// It opens the existing creation menu; it never creates or stores a Task.
final plannerAddRequestProvider = StateProvider<int>((ref) => 0);
