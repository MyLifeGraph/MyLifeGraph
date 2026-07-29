import re
from dataclasses import dataclass

from app.models.coach import CoachModelOutput
from app.providers.base import CoachProviderError


_GERMAN_NON_NEGATING_MODIFIERS = (
    r"(?:(?:\s+(?!(?:nicht|nie|niemals|keinesfalls|"
    r"kein(?:e|en|em|er|es)?)\b)[^\s.!?…,;:]+)){0,8}"
)
_GERMAN_TERMINAL = r"(?=\s*(?:[.!?…]|$|,\s*(?:wenn|weil|bevor)\b))"
_GERMAN_TEMPORAL_PREFIX = (
    r"(?:heute(?:\s+(?:abend|nacht|mittag|morgen))?|"
    r"morgen(?:\s+(?:früh|abend|nacht|mittag))?|"
    r"übermorgen|später|gleich|jetzt|bald)"
)
_GERMAN_DIRECT_CRISIS_PATTERNS = (
    rf"\bich\s+bring(?:e)?\s+mich(?:\s+selbst)?"
    rf"{_GERMAN_NON_NEGATING_MODIFIERS}\s+um{_GERMAN_TERMINAL}",
    rf"\b{_GERMAN_TEMPORAL_PREFIX}\s+bring(?:e)?\s+ich\s+mich"
    rf"(?:\s+selbst)?{_GERMAN_NON_NEGATING_MODIFIERS}\s+um"
    rf"{_GERMAN_TERMINAL}",
    rf"\bich\s+(?:will|möchte|werde|muss|könnte)\s+mich"
    rf"(?:\s+selbst)?{_GERMAN_NON_NEGATING_MODIFIERS}\s+umbringen\b",
    rf"\bich\s+(?:plane|versuche),?\s+mich(?:\s+selbst)?"
    rf"{_GERMAN_NON_NEGATING_MODIFIERS}\s+umzubringen\b",
    rf"\bich\s+habe\s+vor,?\s+mich(?:\s+selbst)?"
    rf"{_GERMAN_NON_NEGATING_MODIFIERS}\s+umzubringen\b",
)
_URGENT_PATTERNS = (
    r"\bkill myself\b",
    r"\bi (?:want|plan|intend) to die\b",
    r"\bend my life\b",
    r"\bsuicid(?:e|al)\b",
    r"\bhurt myself\b",
    r"\boverdose\b",
    r"\bimmediate danger\b",
    *_GERMAN_DIRECT_CRISIS_PATTERNS,
    # Other direct first-person forms remain explicit so nearby figurative
    # language does not turn into a crisis classification.
    r"\bich\s+töte\s+mich(?:\s+selbst)?(?=\s*(?:[.!?…]|$))",
    r"\bich\s+(?:will|werde|möchte)\s+mich(?:\s+selbst)?\s+töten\b",
    r"\bich\s+nehme\s+mir\s+das\s+leben(?=\s*(?:[.!?…]|$))",
    r"\bich\s+(?:will|werde|möchte)\s+mir\s+das\s+leben\s+nehmen\b",
    r"\bich\s+tu(?:e)?\s+mir\s+(?:etwas|was)\s+an"
    r"(?=\s*(?:[.!?…]|$))",
    r"\bich (?:will|möchte|plane) sterben\b",
    r"\bselbstmord\b",
    r"\bsuizid\b",
    r"\bnicht mehr leben\b",
    r"\bmir (?:etwas|was) antun\b",
    r"\bakute gefahr\b",
)

_ENGLISH_DIAGNOSIS_TERM = (
    r"(?:depression|anxiety(?: disorder)?|adhd|ptsd|schizophrenia|psychosis|"
    r"bipolar(?: disorder)?|autism|ocd|"
    r"(?:[a-z][a-z'-]*\s+){0,3}(?:disorder|syndrome|disease))"
)
_GERMAN_DIAGNOSIS_TERM = (
    r"(?:depression(?:en)?|adhs|ptbs|schizophrenie|psychose|autismus|"
    r"(?:[a-zäöüß][a-zäöüß'-]*\s+){0,3}"
    r"[a-zäöüß'-]*(?:störung|syndrom|krankheit))"
)
_ENGLISH_DIAGNOSTIC_ADJECTIVE = (
    r"(?:clinically depressed|depressed|autistic|bipolar|psychotic|schizophrenic)"
)
_GERMAN_DIAGNOSTIC_ADJECTIVE = (
    r"(?:klinisch depressiv|depressiv|autistisch|bipolar|psychotisch|"
    r"schizophren)"
)
_MEDICATION_TERM = (
    r"(?:medication|medicine|meds|prescription|dose|dosage|"
    r"sertraline|fluoxetine|citalopram|escitalopram|paroxetine|"
    r"venlafaxine|duloxetine|bupropion|mirtazapine|lithium|"
    r"quetiapine|olanzapine|risperidone|aripiprazole|"
    r"methylphenidate|amphetamine|lisdexamfetamine|atomoxetine)"
)
_UNSAFE_CLINICAL_PATTERNS = (
    rf"\byou (?:definitely |clearly |certainly )?have (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    r"\bi diagnose (?:you|this|that|it)\b",
    r"\bstop taking (?:your )?medication\b",
    rf"\bdu hast (?:definitiv |eindeutig |sicher )?(?:eine[nmr]? )?"
    rf"{_GERMAN_DIAGNOSIS_TERM}\b",
    r"\bich diagnostiziere (?:dich|bei dir|eine?n?|depression|adhs)\b",
    r"\bsetz(?:e)? .*medikament.* ab\b",
    rf"\b(?:this|that) (?:proves|means|shows) (?:that )?you "
    rf"(?:have|suffer from) (?:an? )?{_ENGLISH_DIAGNOSIS_TERM}\b",
    r"\b(?:increase|decrease|double|halve|change) (?:your )?(?:dose|dosage)\b",
    r"\b(?:start|stop|replace|change|follow) (?:this|that|a|your) "
    r"(?:treatment plan|medical treatment)\b",
    r"\b(?:here is|i (?:recommend|created|made)) (?:a|your) treatment plan\b",
    r"\bi (?:can |will |would )?prescribe (?:you |a |an )?\w+\b",
    rf"\b(?:the )?diagnosis (?:is|confirms?) (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    r"\bdiagnostic criteria (?:are|were) (?:clearly )?met\b",
    rf"\byou are (?:definitely |clearly |certainly )?"
    rf"{_ENGLISH_DIAGNOSTIC_ADJECTIVE}\b",
    rf"\b(?:this|that) is (?:definitely |clearly |certainly )?(?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\byour (?:symptoms|records|data|history|pattern) "
    rf"(?:confirm|prove|establish) (?:a diagnosis of |that you have )?"
    rf"(?:an? )?{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\byou (?:clearly )?meet (?:the )?diagnostic criteria for (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\b(?:these|your) symptoms are diagnostic of (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\b(?:das|dies) (?:beweist|bedeutet|zeigt),? dass du "
    rf"(?:eine[nmr]? )?{_GERMAN_DIAGNOSIS_TERM} hast\b",
    r"\b(?:erhöhe|reduziere|verdopple|halbiere|ändere) "
    r"(?:deine )?(?:dosis|dosierung)\b",
    r"\b(?:beginne|starte|beende|ersetze|folge|ändere) "
    r"(?:diesem|diesen|den|einen|deinen) "
    r"(?:behandlungsplan|medizinische behandlung)\b",
    r"\bich (?:verschreibe|(?:kann|werde|würde) verschreiben) "
    r"(?:dir )?\w+\b",
    rf"\b(?:die )?diagnose (?:ist|bestätigt?) (?:eine[nmr]? )?"
    rf"{_GERMAN_DIAGNOSIS_TERM}\b",
    r"\bdiagnosekriterien (?:sind|wurden) (?:eindeutig )?erfüllt\b",
    rf"\bdu bist (?:definitiv |eindeutig |sicher )?"
    rf"{_GERMAN_DIAGNOSTIC_ADJECTIVE}\b",
    rf"\b(?:das|dies) ist (?:definitiv |eindeutig |sicher )?"
    rf"(?:eine[nmr]? )?{_GERMAN_DIAGNOSIS_TERM}\b",
    rf"\bdeine (?:symptome|daten|aufzeichnungen|historie|muster) "
    rf"(?:bestätigen|beweisen) (?:die diagnose |dass du )?"
    rf"(?:eine[nmr]? )?{_GERMAN_DIAGNOSIS_TERM}\b",
    rf"\byou (?:likely |probably |possibly )?"
    rf"(?:have|suffer from|appear to have) (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\byou (?:may|might|could) (?:have|be suffering from) (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\b(?:this|that|it) (?:likely |probably |possibly )?"
    rf"(?:looks|sounds|seems) like (?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\byour (?:symptoms|records|data|history|pattern) "
    rf"(?:suggest|suggests|indicate|indicates|point|points) (?:to )?(?:an? )?"
    rf"{_ENGLISH_DIAGNOSIS_TERM}\b",
    rf"\b(?:skip|stop|discontinue|quit|withhold|pause|resume|start|"
    rf"double|halve|increase|decrease|change) (?:taking )?(?:your )?"
    rf"{_MEDICATION_TERM}\b",
    rf"\bdu (?:hast vermutlich|hast wahrscheinlich|könntest|könntest eine[nmr]?) "
    rf"(?:eine[nmr]? )?{_GERMAN_DIAGNOSIS_TERM}\b",
)

_ENGLISH_PERSONAL_SIGNAL = (
    r"(?:sleep|stress|mood|energy|focus|habit|routine|workload|screen time|"
    r"movement|exercise|check-ins?|calendar|schedule|bedtime|sleep timing|"
    r"wake time)"
)
_ENGLISH_PERSONAL_OUTCOME = (
    r"(?:sleep|stress|mood|energy|focus|productivity|performance|progress|"
    r"task(?: completion)?|missed tasks?|habit|routine|anxiety|depression|"
    r"health|concentration|attention|focused|grades?)"
)
_GERMAN_PERSONAL_SIGNAL = (
    r"(?:schlaf|stress|stimmung|energie|fokus|gewohnheit|routine|arbeitslast|"
    r"bildschirmzeit|bewegung|sport|check-ins?|kalender|zeitplan)"
)
_GERMAN_PERSONAL_OUTCOME = (
    r"(?:schlaf|stress|stimmung|energie|fokus|produktivität|leistung|fortschritt|"
    r"aufgabenerledigung|verpasste aufgaben?|gewohnheit|routine|angst|depression|"
    r"gesundheit)"
)
_UNSAFE_PERSONAL_CAUSAL_PATTERNS = (
    rf"\b(?:your|the recorded)\s+(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_SIGNAL}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>caused|causes|led to|resulted in|explains|"
    rf"is responsible for)\b[^.!?\n]{{0,80}}\b"
    rf"(?:your\s+)?(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_OUTCOME}\b",
    rf"\b(?:your\s+)?(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_OUTCOME}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>was caused by|is caused by|is due to|resulted from)\b"
    rf"[^.!?\n]{{0,80}}\byour\s+(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_SIGNAL}\b",
    rf"(?P<causal>\bbecause of\b|\bdue to\b)\s+your\s+"
    rf"(?:[a-z][a-z'-]*\s+){{0,3}}{_ENGLISH_PERSONAL_SIGNAL}\b"
    rf"[^.!?\n]{{0,100}}\byour\s+(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_OUTCOME}\b",
    rf"\b(?:your|the app|these|the recorded)\s+(?:data|records)\b"
    rf"[^.!?\n]{{0,100}}\b(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_SIGNAL}\b[^.!?\n]{{0,60}}\b"
    rf"(?P<causal>caused|causes|led to|resulted in|explains)\b"
    rf"[^.!?\n]{{0,80}}\b(?:your\s+)?(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_OUTCOME}\b",
    rf"\bdein(?:e|er|em|en|es)?\s+(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_SIGNAL}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>verursacht|verursachte|führte zu|führt zu|"
    rf"erklärt|ist verantwortlich für)\b[^.!?\n]{{0,80}}\b"
    rf"(?:dein(?:e|er|em|en|es)?\s+)?"
    rf"(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_OUTCOME}\b",
    rf"\bdein(?:e|er|em|en|es)?\s+"
    rf"(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_OUTCOME}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>wurde verursacht durch|ist verursacht durch|"
    rf"ist zurückzuführen auf|resultierte aus)\b[^.!?\n]{{0,80}}\b"
    rf"dein(?:e|er|em|en|es)?\s+"
    rf"(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_SIGNAL}\b",
    rf"\byour\s+(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_SIGNAL}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>made|triggered|drove|worsened|improved|reduced|"
    rf"increased|produced|created|determined|accounts for|is why)\b"
    rf"[^.!?\n]{{0,80}}\b(?:your\s+)?"
    rf"(?:[a-z][a-z'-]*\s+){{0,3}}{_ENGLISH_PERSONAL_OUTCOME}\b",
    rf"\byour\s+(?:[a-z][a-z'-]*\s+){{0,3}}"
    rf"{_ENGLISH_PERSONAL_OUTCOME}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>stems from|comes from|was triggered by|was driven by|"
    rf"was worsened by|was improved by)\b[^.!?\n]{{0,80}}\byour\s+"
    rf"(?:[a-z][a-z'-]*\s+){{0,3}}{_ENGLISH_PERSONAL_SIGNAL}\b",
    rf"\bdein(?:e|er|em|en|es)?\s+"
    rf"(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_SIGNAL}\b[^.!?\n]{{0,80}}\b"
    rf"(?P<causal>bewirkte|bewirkt|löste aus|löst aus|trieb|"
    rf"verschlechterte|verbesserte|bestimmte)\b[^.!?\n]{{0,80}}\b"
    rf"(?:dein(?:e|er|em|en|es)?\s+)?"
    rf"(?:[a-zäöüß][a-zäöüß'-]*\s+){{0,3}}"
    rf"{_GERMAN_PERSONAL_OUTCOME}\b",
)
_CAUSAL_DISCLAIMER_PATTERNS = (
    r"\b(?:cannot|can't|could not|does not|doesn't|do not|don't) "
    r"(?:establish|show|prove|determine|tell|mean)\b",
    r"\b(?:no|not enough) evidence\b",
    r"\b(?:unclear|unknown) whether\b",
    r"\b(?:kann|können|konnte|konnten) (?:nicht )?"
    r"(?:belegen|zeigen|beweisen|bestimmen|sagen)\b",
    r"\b(?:keine|nicht genug) evidenz\b",
    r"\b(?:unklar|unbekannt),? ob\b",
)
_UNSAFE_MUTATION_CLAIM_PATTERNS = (
    r"\bi(?:'ve| have| have just| just| already| successfully)?\s+"
    r"(?:created|added|updated|edited|deleted|removed|scheduled|rescheduled|"
    r"cancelled|canceled|completed|accepted|dismissed|archived|paused|"
    r"started|stopped|changed|saved|set|enabled|disabled) "
    r"(?:an? |the |your )?(?:task|habit|calendar event|event|notification|"
    r"reminder|plan|schedule|goal|memory|setting|focus session)\b",
    r"\bi(?:'ve|'ll| will| can| am going to) "
    r"(?:create|add|update|edit|delete|remove|schedule|reschedule|cancel|"
    r"complete|accept|dismiss|archive|pause|start|stop|change|save|set|"
    r"enable|disable) (?:an? |the |your )?"
    r"(?:task|habit|calendar event|event|notification|reminder|plan|schedule|"
    r"goal|memory|setting|focus session)\b",
    r"\b(?:your |the )?(?:task|habit|calendar event|event|notification|"
    r"reminder|plan|schedule|goal|memory|setting|focus session) "
    r"(?:has been|was|is now) (?:created|added|updated|edited|deleted|removed|"
    r"scheduled|rescheduled|cancelled|canceled|completed|accepted|dismissed|"
    r"archived|paused|started|stopped|changed|saved|set|enabled|disabled)\b",
)


@dataclass(frozen=True)
class CoachSafetyDecision:
    bypass_provider: bool
    output: CoachModelOutput | None = None


@dataclass(frozen=True)
class CoachPostProviderSafetyResult:
    output: CoachModelOutput
    replaced_with_deterministic_safety: bool


def pre_provider_safety(
    message: str,
    *,
    force_english: bool = False,
) -> CoachSafetyDecision:
    if not _matches_any(message, _URGENT_PATTERNS):
        return CoachSafetyDecision(bypass_provider=False)
    german = not force_english and _looks_german(message)
    reply = (
        "Es klingt, als könntest du gerade unmittelbar gefährdet sein. "
        "Bitte kontaktiere jetzt den örtlichen Notruf oder eine Krisenhilfe und "
        "bleib, wenn möglich, bei einer vertrauten Person. Dieser Coach ist kein "
        "Notfalldienst und kann deine Sicherheit nicht überwachen."
        if german
        else "It sounds like you may be in immediate danger. Please contact your "
        "local emergency service or crisis support now and, if possible, stay "
        "with a trusted person. This Coach is not an emergency service and cannot "
        "monitor your safety."
    )
    return CoachSafetyDecision(
        bypass_provider=True,
        output=CoachModelOutput(
            reply=reply,
            uncertainty={
                "level": "high",
                "reason": (
                    "Die Situation kann hier nicht sicher beurteilt werden."
                    if german
                    else "This situation cannot be safely assessed here."
                ),
            },
            staged_suggestion=None,
            safety={"classification": "safety_redirect"},
        ),
    )


def post_provider_safety(
    output: CoachModelOutput,
    *,
    message: str,
    force_english: bool = False,
) -> CoachPostProviderSafetyResult:
    if output.safety.classification == "safety_redirect":
        decision = pre_provider_safety(
            message,
            force_english=force_english,
        )
        if decision.output is not None:
            return CoachPostProviderSafetyResult(
                output=decision.output,
                replaced_with_deterministic_safety=True,
            )
        # The provider may recognize urgent wording that the deterministic
        # detector missed. Use backend-owned copy, never provider-authored crisis copy.
        german = not force_english and _looks_german(message)
        return CoachPostProviderSafetyResult(
            output=CoachModelOutput(
                reply=(
                    "Das könnte sofortige menschliche Unterstützung erfordern. Bitte "
                    "kontaktiere jetzt den örtlichen Notruf oder eine Krisenhilfe und "
                    "bleib, wenn möglich, bei einer vertrauten Person. Dieser Coach "
                    "kann deine Sicherheit nicht überwachen."
                    if german
                    else "This may require immediate human support. Please contact your "
                    "local emergency service or crisis support now and, if possible, "
                    "stay with a trusted person. This Coach cannot monitor your safety."
                ),
                uncertainty={
                    "level": "high",
                    "reason": (
                        "Die Situation kann hier nicht sicher beurteilt werden."
                        if german
                        else "This situation cannot be safely assessed here."
                    ),
                },
                staged_suggestion=None,
                safety={"classification": "safety_redirect"},
            ),
            replaced_with_deterministic_safety=True,
        )
    if any(
        _matches_any(text, _UNSAFE_CLINICAL_PATTERNS)
        or _contains_unsupported_personal_causal_claim(text)
        or _matches_any(text, _UNSAFE_MUTATION_CLAIM_PATTERNS)
        for text in _user_rendered_model_text(output)
    ):
        raise CoachProviderError(
            "invalid_output",
            "The Coach output crossed the non-clinical or non-causal boundary.",
            retryable=True,
        )
    return CoachPostProviderSafetyResult(
        output=output,
        replaced_with_deterministic_safety=False,
    )


def force_missing_state_uncertainty(
    output: CoachModelOutput,
    *,
    daily_state_freshness: str,
) -> CoachModelOutput:
    if (
        output.safety.classification == "safety_redirect"
        or daily_state_freshness not in {"missing", "stale"}
    ):
        return output
    reason = (
        "Today's deterministic Daily State is missing, so this answer must remain "
        "highly uncertain."
        if daily_state_freshness == "missing"
        else "Today's deterministic Daily State is stale, so this answer must remain "
        "highly uncertain."
    )
    return output.model_copy(
        update={
            "uncertainty": output.uncertainty.model_copy(
                update={"level": "high", "reason": reason},
            ),
        },
    )


def force_historical_evidence_uncertainty(
    output: CoachModelOutput,
    *,
    evidence_status: str,
) -> CoachModelOutput:
    if (
        output.safety.classification == "safety_redirect"
        or evidence_status not in {"empty", "sparse", "partial"}
    ):
        return output
    reason = {
        "empty": (
            "No eligible historical evidence was available, so this answer must "
            "remain highly uncertain."
        ),
        "sparse": (
            "Only sparse historical evidence was available, so this answer must "
            "remain highly uncertain."
        ),
        "partial": (
            "At least one historical source was only partially processed, so this "
            "answer must remain highly uncertain."
        ),
    }[evidence_status]
    return output.model_copy(
        update={
            "uncertainty": output.uncertainty.model_copy(
                update={"level": "high", "reason": reason},
            ),
        },
    )


def _matches_any(value: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(pattern, value, flags=re.IGNORECASE) for pattern in patterns)


def _contains_unsupported_personal_causal_claim(value: str) -> bool:
    for pattern in _UNSAFE_PERSONAL_CAUSAL_PATTERNS:
        for match in re.finditer(pattern, value, flags=re.IGNORECASE):
            causal_start = match.start("causal")
            boundary = max(
                value.rfind(character, 0, causal_start)
                for character in ".!?;\n"
            )
            prefix = value[boundary + 1 : causal_start]
            contrasts = list(
                re.finditer(
                    r"\b(?:but|however|yet|nevertheless|aber|jedoch|doch)\b",
                    prefix,
                    flags=re.IGNORECASE,
                ),
            )
            if contrasts:
                prefix = prefix[contrasts[-1].end() :]
            if not _matches_any(prefix, _CAUSAL_DISCLAIMER_PATTERNS):
                return True
    return False


def _user_rendered_model_text(output: CoachModelOutput) -> tuple[str, ...]:
    values = [output.reply, output.uncertainty.reason]
    if output.staged_suggestion is not None:
        values.extend(
            [
                output.staged_suggestion.title,
                output.staged_suggestion.rationale,
            ],
        )
    return tuple(values)


def _looks_german(value: str) -> bool:
    lowered = value.lower()
    return bool(
        re.search(
            r"\b(?:ich|mich|nicht|selbst|gefahr|hilfe|sterben)\b|[äöüß]",
            lowered,
        ),
    )
