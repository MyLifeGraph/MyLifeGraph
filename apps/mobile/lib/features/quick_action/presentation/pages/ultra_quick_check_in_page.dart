import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../composition/profile_local_date_providers.dart';
import '../../../../composition/quick_capture_providers.dart';
import '../../../../composition/widgets/capture_dictation_input.dart';
import '../../../../composition/widgets/assistant_language_button.dart';
import '../../../../core/preferences/assistant_language.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../domain/capture_draft_proposal.dart';
import '../../domain/quick_capture_api.dart';

class UltraQuickCheckInPage extends ConsumerStatefulWidget {
  const UltraQuickCheckInPage({super.key});

  @override
  ConsumerState<UltraQuickCheckInPage> createState() =>
      _UltraQuickCheckInPageState();
}

class _UltraQuickCheckInPageState extends ConsumerState<UltraQuickCheckInPage> {
  String get _speakingGuide {
    if (ref.read(assistantLanguageProvider('capture')).value == 'de') {
      return _mode == 'morning'
          ? 'Eingeschlafen: … · Aufgewacht: …\n'
              'Schlafqualität: … / 10\n'
              'Aktuelle Energie: … / 10\n'
              'Lernmotivation (optional): Niedrig / Mittel / Hoch'
          : 'Stimmung: … / 10\n'
              'Übrige Energie: … / 10\n'
              'Stress: … / 10\n'
              'Geplanter Schlafbeginn: …\n'
              'Schlafziel: … Stunden\n'
              'Bei Stress ≥ 5: Ursache …; Einfluss Wenig / Teilweise / Überwiegend\n'
              'Reflexion (optional): …\n'
              'Konkretes Hindernis (optional): …\n'
              'Sport (optional): Kein / Leicht / Intensiv\n'
              'Soziale Kontakte (optional): Wenig / Einige / Viele';
    }
    return _mode == 'morning'
      ? 'Sleep start: … · Wake time: …\n'
            'Sleep quality: … / 10\n'
            'Current energy: … / 10\n'
            'Study motivation (optional): Low / Medium / High'
      : 'Mood: … / 10\n'
            'Energy left: … / 10\n'
            'Stress: … / 10\n'
            'Planned sleep start: …\n'
            'Sleep duration target: … hours\n'
            'If stress ≥ 5: source …; influence Little / Some / Mostly\n'
            'Reflection (optional): …\n'
            'Specific blocker (optional): …\n'
            'Sport (optional): None / Light / Intense\n'
            'Social contact (optional): Little / Some / Lots';
  }

  final _text = TextEditingController();
  String _lastText = '';
  String _mode = 'morning';
  String _requestId = newClientUuid();
  (String, String)? _draftContext;
  String? _noteTimezone;
  String? _owner;
  String? _error;
  bool _busy = false;
  bool _recording = false;
  int _generation = 0;
  List<QuickNote> _notes = [];
  String? _cursor;
  bool _notesLoaded = false;
  bool _notesBusy = false;
  String? _notesError;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(quickCaptureProfileIdProvider);
    _text.addListener(_changed);
  }

  void _changed() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    _requestId = newClientUuid();
    _noteTimezone = null;
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _generation++;
    _text.dispose();
    super.dispose();
  }

  bool _current(int generation, String owner) =>
      mounted &&
      generation == _generation &&
      ref.read(quickCaptureProfileIdProvider) == owner;

  Future<void> _submit() async {
    final owner = ref.read(quickCaptureProfileIdProvider);
    final text = _text.text.trim();
    if (_busy || _recording || _notesBusy || owner == null || text.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final mode = _mode;
    final localDate = ref.read(profileLocalDateSourceProvider);
    final timezone = mode == 'note'
        ? _noteTimezone ?? localDate.timezoneName
        : localDate.timezoneName;
    final today = localDate.todayKey();
    if (timezone == null) return;
    if (mode == 'note') {
      // A lost save response may already be committed. Keep its whole payload
      // for exact replay even if the profile timezone changes before retry.
      _noteTimezone = timezone;
    } else {
      final context = (today, timezone);
      // An unchanged draft retries its exact identity. A new local day or
      // timezone is a different explicit review, not a replay of that request.
      if (_draftContext != null && _draftContext != context) {
        _requestId = newClientUuid();
      }
      _draftContext = context;
    }
    final requestId = _requestId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(quickCaptureApiProvider);
      if (mode == 'note') {
        final note = await api.saveNote(
          noteId: requestId,
          timezone: timezone,
          text: text,
        );
        if (!mounted || !_current(generation, owner)) return;
        _text.clear();
        setState(() {
          _notes = [note, ..._notes.where((value) => value.id != note.id)];
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Note saved.')));
      } else {
        final json = await api.propose(
          requestId: requestId,
          branch: mode,
          transcript: text,
        );
        if (!mounted || !_current(generation, owner)) return;
        final proposal = CaptureDraftProposal.fromJson(json, ownerId: owner);
        if (proposal.requestId != requestId ||
            !proposal.matches(
              ownerId: owner,
              entryDate: today,
              timezone: timezone,
              branch: mode,
            ) ||
            proposal.evidence.values.any((quote) => !text.contains(quote))) {
          throw const FormatException('Draft does not match this request.');
        }
        final currentDate = ref.read(profileLocalDateSourceProvider);
        if (currentDate.todayKey() != today ||
            currentDate.timezoneName != timezone) {
          setState(() => _error = 'Your local day changed. Review again.');
          _requestId = newClientUuid();
          return;
        }
        await context.push(
          mode == 'morning'
              ? AppRoutes.morningCalibration
              : AppRoutes.quickMoodCheckIn,
          extra: proposal,
        );
        // A new explicit review is a new operation, never an automatic retry.
        if (_current(generation, owner)) _requestId = newClientUuid();
      }
    } catch (error) {
      if (!_current(generation, owner)) return;
      final failure = apiFailureFrom(error);
      final data = failure?.responseData;
      final detail = data is Map ? data['detail'] : null;
      if (mode != 'note' &&
          failure?.statusCode == 409 &&
          detail is Map &&
          detail['code'] == 'draft_expired') {
        _requestId = newClientUuid();
        setState(
          () => _error =
              'The previous draft expired. Review again uses a new Coach request.',
        );
        return;
      }
      setState(
        () => _error = mode == 'note'
            ? failure?.statusCode == 409
                  ? 'Note not confirmed. Your text is kept. Check saved notes before editing and saving a new note.'
                  : 'Note not confirmed. Your text is kept; try again.'
            : failure?.statusCode == 429
            ? 'Check-in drafting is busy or at its request limit. Your text is kept. Try again later or use the form.'
            : 'Could not prepare your check-in. Your text is kept. Try again or use the form.',
      );
    } finally {
      if (_current(generation, owner)) setState(() => _busy = false);
    }
  }

  Future<void> _loadNotes({bool more = false}) async {
    final owner = ref.read(quickCaptureProfileIdProvider);
    if (owner == null || _notesBusy || _busy || _recording) return;
    final generation = _generation;
    setState(() {
      _notesBusy = true;
      _notesError = null;
    });
    try {
      final page = await ref
          .read(quickCaptureApiProvider)
          .notes(before: more ? _cursor : null);
      if (!_current(generation, owner)) return;
      setState(() {
        _notes = more
            ? [
                ..._notes,
                ...page.notes.where(
                  (note) => !_notes.any((saved) => saved.id == note.id),
                ),
              ]
            : page.notes;
        _cursor = page.nextCursor;
        _notesLoaded = true;
      });
    } catch (_) {
      if (_current(generation, owner)) {
        setState(() => _notesError = 'Notes could not be loaded.');
      }
    } finally {
      if (_current(generation, owner)) setState(() => _notesBusy = false);
    }
  }

  Future<void> _delete(QuickNote note) async {
    final owner = ref.read(quickCaptureProfileIdProvider);
    if (owner == null || _busy || _recording || _notesBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This removes the saved note from your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        ref.read(quickCaptureProfileIdProvider) != owner) {
      return;
    }
    final generation = _generation;
    setState(() => _notesBusy = true);
    try {
      await ref.read(quickCaptureApiProvider).deleteNote(note.id);
      if (_current(generation, owner)) {
        setState(() => _notes.removeWhere((item) => item.id == note.id));
      }
    } catch (_) {
      if (_current(generation, owner)) {
        setState(() => _notesError = 'Deletion not confirmed. Try again.');
      }
    } finally {
      if (_current(generation, owner)) setState(() => _notesBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(quickCaptureProfileIdProvider);
    ref.listen(quickCaptureProfileIdProvider, (_, next) {
      if (next == _owner) return;
      _generation++;
      _owner = next;
      _text.clear();
      _requestId = newClientUuid();
      _noteTimezone = null;
      setState(() {
        _busy = false;
        _recording = false;
        _notesBusy = false;
        _notes = [];
        _cursor = null;
        _notesLoaded = false;
        _notesError = null;
      });
    });
    final locked = _busy || _recording || _notesBusy;
    ref.watch(assistantLanguageProvider('capture'));
    final canRecord = ref
        .watch(appSurfaceCapabilitiesProvider)
        .canAccessCoachBackend;
    return Scaffold(
      body: AppPage(
        title: 'Ultra Quick Check-in',
        compactHeader: true,
        backFallback: AppRoutes.quickAction,
        maxWidth: 680,
        actions: [AssistantLanguageButton(scope: 'capture', enabled: !locked)],
        children: [
          if (owner == null)
            const AppCard(
              child: Text('Sign in to use voice check-ins and cloud notes.'),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final option in [
                  ('morning', 'Morning', AppIcons.wbSunnyOutlined),
                  ('evening', 'Evening', AppIcons.nightsStayOutlined),
                  ('note', 'Quick note', AppIcons.editNoteOutlined),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChoiceChip(
                        showCheckmark: false,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        label: SizedBox(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(option.$3, size: 18),
                              const SizedBox(height: AppSpacing.xs),
                              Text(option.$2, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                        selected: _mode == option.$1,
                        onSelected: locked
                            ? null
                            : (_) {
                                setState(() {
                                  _mode = option.$1;
                                  _requestId = newClientUuid();
                                  _noteTimezone = null;
                                  _error = null;
                                });
                              },
                      ),
                    ),
                  ),
              ],
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _mode == 'note'
                        ? 'Extra context for your Coach. Not a check-in.'
                        : 'Review before saving · uses one Coach request',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_recording && _mode != 'note')
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Speaking guide',
                      ),
                      child: Text(
                        _speakingGuide,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    TextField(
                      controller: _text,
                      enabled: !locked,
                      minLines: 4,
                      maxLines: 20,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: _mode == 'note'
                            ? 'Your note'
                            : 'Tell us about your day',
                        hintMaxLines: 20,
                        hintText: _mode == 'note'
                            ? 'Anything worth remembering…'
                            : _speakingGuide,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  CaptureDictationInput(
                    enabled: !_busy && !_notesBusy && canRecord,
                    onBusyChanged: (value) {
                      if (mounted) setState(() => _recording = value);
                    },
                    onText: (value) {
                      final joined = '${_text.text.trim()} ${value.trim()}'
                          .trim();
                      if (joined.length > 2000) {
                        setState(
                          () => _error =
                              'Keep your note under 2,000 characters. Your recording was not added.',
                        );
                        return;
                      }
                      _text.text = joined;
                    },
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: locked || _text.text.trim().isEmpty
                        ? null
                        : _submit,
                    icon: Icon(
                      _mode == 'note'
                          ? AppIcons.saveOutlined
                          : AppIcons.chevronRight,
                    ),
                    label: Text(
                      _mode == 'note' ? 'Save note' : 'Review fields',
                    ),
                  ),
                  if (_mode != 'note')
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => context.push(
                              _mode == 'morning'
                                  ? AppRoutes.morningCalibration
                                  : AppRoutes.quickMoodCheckIn,
                            ),
                      child: const Text('Use the form instead'),
                    ),
                ],
              ),
            ),
            if (_mode == 'note')
              AppCard(
                child: ExpansionTile(
                  enabled: !_busy && !_recording,
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Saved notes'),
                  onExpansionChanged: (open) {
                    if (open && !_notesLoaded) _loadNotes();
                  },
                  children: [
                    if (_notesBusy) const LinearProgressIndicator(),
                    if (_notesError != null)
                      Row(
                        children: [
                          Expanded(child: Text(_notesError!)),
                          IconButton(
                            tooltip: 'Retry loading notes',
                            onPressed: _notesBusy ? null : _loadNotes,
                            icon: const Icon(AppIcons.refresh),
                          ),
                        ],
                      ),
                    if (_notesLoaded && _notes.isEmpty)
                      const Text('No saved notes yet.'),
                    for (final note in _notes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(note.text),
                        subtitle: Text(note.entryDate),
                        trailing: IconButton(
                          tooltip: 'Delete note',
                          onPressed: locked ? null : () => _delete(note),
                          icon: const Icon(AppIcons.deleteOutline),
                        ),
                      ),
                    if (_cursor != null)
                      TextButton(
                        onPressed: locked ? null : () => _loadNotes(more: true),
                        child: const Text('Load more'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
