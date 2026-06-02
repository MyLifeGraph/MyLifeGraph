import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/coach_supabase_service.dart';

class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final TextEditingController _controller = TextEditingController(
    text: 'Plan my day based on my current energy and deadlines',
  );
  final List<_ChatMessage> _messages = [];
  CoachSupabaseService? _coachService;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadMessages);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      return;
    }
    _coachService = CoachSupabaseService(client);
    try {
      final messages = await _coachService!.getMessages();
      if (!mounted || messages.isEmpty) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(
            messages.map(
              (message) => _ChatMessage(
                text: message.text,
                isUser: message.isUser,
              ),
            ),
          );
      });
    } on PostgrestException {
      return;
    } catch (_) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    0,
                  ),
                  sliver: SliverList.list(
                    children: [
                      const _CoachHeader(),
                      const SizedBox(height: AppSpacing.xl),
                      _ChatPanel(messages: _messages),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _CoachInput(
            controller: _controller,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    const response =
        'Got it. I will use your check-ins, alerts, and schedule context to suggest the next useful step.';

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _messages.add(const _ChatMessage(text: response, isUser: false));
      _controller.clear();
    });

    try {
      await _coachService?.addMessage(text: text, isUser: true);
      await _coachService?.addMessage(text: response, isUser: false);
    } catch (_) {
      return;
    }
  }
}

class _CoachHeader extends StatelessWidget {
  const _CoachHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI COACH',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 4,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Coach Chat',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 48,
                      height: 1,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Personal planning, motivation, and focus coaching based on your check-ins, timetable, alerts, and memory.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFA8B5BE),
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF15242A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF2A424A), width: 2),
          ),
          child: Icon(
            Icons.smart_toy_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.messages});

  final List<_ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 560),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2A424A), width: 2),
      ),
      child: Column(
        children: [
          ...messages.map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Align(
                alignment: message.isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: _ChatBubble(message: message),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFF242B34),
          borderRadius: BorderRadius.circular(message.isUser ? 28 : 22),
        ),
        child: Text(
          message.text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: message.isUser ? Colors.black : const Color(0xFFEFF4F6),
              ),
        ),
      ),
    );
  }
}

class _CoachInput extends StatelessWidget {
  const _CoachInput({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1218),
        border: Border(top: BorderSide(color: Color(0xFF2A424A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Plan my day based on my current energy and deadlines',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF2A424A)),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 58,
            height: 58,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onSend,
              child: const Icon(Icons.send_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;
}
