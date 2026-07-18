import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/guest_setup_data_source.dart';
import '../../data/intake_setup_repository.dart';
import '../../domain/app_session.dart';
import '../../domain/intake_response.dart';
import 'auth_providers.dart';

final guestSetupDataSourceProvider = Provider<GuestSetupDataSource>(
  (_) => const GuestSetupDataSource(),
);

final intakeSetupRepositoryProvider = Provider<IntakeSetupGateway>((ref) {
  return IntakeSetupRepository(
    apiDataSource: ref.watch(intakeApiDataSourceProvider),
    guestDataSource: ref.watch(guestSetupDataSourceProvider),
    supabaseClient: ref.watch(supabaseClientProvider),
    useMockData: ref.watch(appConfigProvider).useMockData,
  );
});

final setupControllerProvider =
    StateNotifierProvider.autoDispose<SetupController, SetupEditorState>((ref) {
  final session = ref.read(authControllerProvider).valueOrNull;
  return SetupController(
    repository: ref.watch(intakeSetupRepositoryProvider),
    session: session,
    onApplied: (responses) {
      if (session?.requiresOnboarding != true) {
        return;
      }
      ref.read(authControllerProvider.notifier).markOnboardingComplete(
            displayName: responses.displayName,
          );
    },
  );
});

class SetupEditorState {
  const SetupEditorState({
    required this.isLoading,
    required this.isSaving,
    required this.readState,
    required this.draft,
    required this.requestId,
    required this.loadError,
    required this.saveError,
    required this.retryLocked,
    required this.reloadSuggested,
  });

  const SetupEditorState.loading()
      : isLoading = true,
        isSaving = false,
        readState = null,
        draft = null,
        requestId = null,
        loadError = null,
        saveError = null,
        retryLocked = false,
        reloadSuggested = false;

  final bool isLoading;
  final bool isSaving;
  final IntakeSetupReadState? readState;
  final IntakeResponseDraft? draft;
  final String? requestId;
  final Object? loadError;
  final Object? saveError;
  final bool retryLocked;
  final bool reloadSuggested;

  bool get canSave =>
      !isLoading && !isSaving && draft != null && requestId != null;

  bool get isPending => readState?.status == 'pending';
  bool get isEditLocked => isPending || retryLocked;

  SetupEditorState copyWith({
    bool? isLoading,
    bool? isSaving,
    Object? readState = _unset,
    Object? draft = _unset,
    Object? requestId = _unset,
    Object? loadError = _unset,
    Object? saveError = _unset,
    bool? retryLocked,
    bool? reloadSuggested,
  }) {
    return SetupEditorState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      readState: identical(readState, _unset)
          ? this.readState
          : readState as IntakeSetupReadState?,
      draft:
          identical(draft, _unset) ? this.draft : draft as IntakeResponseDraft?,
      requestId:
          identical(requestId, _unset) ? this.requestId : requestId as String?,
      loadError: identical(loadError, _unset) ? this.loadError : loadError,
      saveError: identical(saveError, _unset) ? this.saveError : saveError,
      retryLocked: retryLocked ?? this.retryLocked,
      reloadSuggested: reloadSuggested ?? this.reloadSuggested,
    );
  }
}

class SetupController extends StateNotifier<SetupEditorState> {
  SetupController({
    required IntakeSetupGateway repository,
    required AppSession? session,
    required void Function(IntakeResponseDraft responses) onApplied,
  })  : _repository = repository,
        _session = session,
        _onApplied = onApplied,
        super(const SetupEditorState.loading()) {
    Future<void>.microtask(load);
  }

  final IntakeSetupGateway _repository;
  final AppSession? _session;
  final void Function(IntakeResponseDraft responses) _onApplied;

  AppSession? get session => _session;

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      isSaving: false,
      loadError: null,
      saveError: null,
      retryLocked: false,
      reloadSuggested: false,
    );
    final session = _session;
    if (session == null) {
      state = state.copyWith(
        isLoading: false,
        loadError: StateError('No active session.'),
      );
      return;
    }
    try {
      final readState = await _repository.fetch(session);
      final profileName = session.profile.name.trim();
      final loadedDraft = readState.responses ??
          IntakeResponseDraft.empty(
            displayName: session.isGuestSession || profileName.isEmpty
                ? null
                : profileName,
          );
      if (readState.status == 'pending' &&
          (readState.requestId == null || !isSetupUuid(readState.requestId!))) {
        throw const FormatException(
          'Pending setup state is missing a valid request id.',
        );
      }
      final initialDraft = readState.status == 'pending'
          ? loadedDraft
          : repairSetupItemKeys(loadedDraft);
      state = SetupEditorState(
        isLoading: false,
        isSaving: false,
        readState: readState,
        draft: initialDraft,
        requestId: readState.status == 'pending'
            ? readState.requestId
            : generateSetupUuid(),
        loadError: null,
        saveError: null,
        retryLocked: false,
        reloadSuggested: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        loadError: error,
      );
    }
  }

  void updateDraft(IntakeResponseDraft draft) {
    if (state.isSaving || state.isEditLocked) {
      return;
    }
    state = state.copyWith(draft: draft, saveError: null);
  }

  Future<bool> save() async {
    final session = _session;
    final currentReadState = state.readState;
    final requestId = state.requestId;
    final draft = state.draft?.normalized();
    if (session == null ||
        currentReadState == null ||
        requestId == null ||
        draft == null) {
      state = state.copyWith(
        saveError: StateError('Setup is not ready to save.'),
      );
      return false;
    }
    final validationErrors = draft.validationErrors();
    if (validationErrors.isNotEmpty) {
      state = state.copyWith(saveError: StateError(validationErrors.first));
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      draft: draft,
      saveError: null,
      reloadSuggested: false,
    );
    late final IntakeSetupReadState saved;
    try {
      saved = await _repository.save(
        session,
        IntakeSetupSaveRequest(
          requestId: requestId,
          baseRevision: currentReadState.status == 'pending'
              ? currentReadState.baseRevision
              : currentReadState.revision,
          responses: draft,
        ),
      );
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        saveError: error,
        retryLocked: setupSaveRequiresExactRetry(error),
        reloadSuggested: setupSaveSuggestsReload(error),
      );
      return false;
    }
    final savedResponses = saved.responses;
    if (!saved.exists || saved.status != 'applied' || savedResponses == null) {
      state = state.copyWith(
        isSaving: false,
        saveError: const FormatException(
          'The setup save response did not contain applied setup state.',
        ),
        retryLocked: true,
        reloadSuggested: false,
      );
      return false;
    }
    state = SetupEditorState(
      isLoading: false,
      isSaving: false,
      readState: saved,
      draft: savedResponses,
      requestId: generateSetupUuid(),
      loadError: null,
      saveError: null,
      retryLocked: false,
      reloadSuggested: false,
    );
    _onApplied(savedResponses);
    return true;
  }
}

bool setupSaveRequiresExactRetry(Object error) {
  if (error is GuestSetupRevisionException ||
      error is GuestSetupIdempotencyException) {
    return false;
  }
  final statusCode = _dioExceptionFrom(error)?.response?.statusCode;
  if (statusCode != null && statusCode >= 400 && statusCode < 500) {
    return false;
  }
  return true;
}

bool setupSaveSuggestsReload(Object error) {
  if (error is GuestSetupRevisionException ||
      error is GuestSetupIdempotencyException) {
    return true;
  }
  return _dioExceptionFrom(error)?.response?.statusCode == 409;
}

DioException? _dioExceptionFrom(Object error) {
  if (error is DioException) {
    return error;
  }
  final cause = error is AppException ? error.cause : null;
  return cause is DioException ? cause : null;
}

const Object _unset = Object();
