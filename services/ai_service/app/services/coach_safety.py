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
)


@dataclass(frozen=True)
class CoachSafetyDecision:
    bypass_provider: bool
    output: CoachModelOutput | None = None


@dataclass(frozen=True)
class CoachPostProviderSafetyResult:
    output: CoachModelOutput
    replaced_with_deterministic_safety: bool


def pre_provider_safety(message: str) -> CoachSafetyDecision:
    if not _matches_any(message, _URGENT_PATTERNS):
        return CoachSafetyDecision(bypass_provider=False)
    german = _looks_german(message)
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
) -> CoachPostProviderSafetyResult:
    if output.safety.classification == "safety_redirect":
        decision = pre_provider_safety(message)
        if decision.output is not None:
            return CoachPostProviderSafetyResult(
                output=decision.output,
                replaced_with_deterministic_safety=True,
            )
        # The provider may recognize urgent wording that the deterministic
        # detector missed. Use backend-owned copy, never provider-authored crisis copy.
        german = _looks_german(message)
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
        for text in _user_rendered_model_text(output)
    ):
        raise CoachProviderError(
            "invalid_output",
            "The Coach output crossed the non-clinical safety boundary.",
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


def _matches_any(value: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(pattern, value, flags=re.IGNORECASE) for pattern in patterns)


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
