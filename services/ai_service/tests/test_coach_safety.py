import pytest

from app.models.coach import CoachModelOutput
from app.providers.base import CoachProviderError
from app.services.coach_safety import (
    force_missing_state_uncertainty,
    post_provider_safety,
    pre_provider_safety,
)


@pytest.mark.parametrize(
    ("message", "german"),
    [
        ("I want to die.", False),
        ("I plan to kill myself.", False),
        ("Ich will sterben.", True),
        ("Ich möchte mich umbringen.", True),
        ("Ich bringe mich um.", True),
        ("Ich bring mich um!", True),
        ("Ich bringe mich heute um.", True),
        ("Ich bringe mich morgen um.", True),
        ("Ich bringe mich später um.", True),
        ("Ich bringe mich heute Abend um.", True),
        ("Ich bringe mich morgen ohne Abschied um.", True),
        ("Ich bringe mich um, wenn das so weitergeht.", True),
        ("Morgen bringe ich mich um.", True),
        ("Ich werde mich morgen umbringen.", True),
        ("Ich will mich heute Abend umbringen.", True),
        ("Ich plane, mich morgen umzubringen.", True),
        ("Ich habe vor, mich morgen umzubringen.", True),
        ("Ich töte mich selbst.", True),
        ("Ich will mich töten.", True),
        ("Ich nehme mir das Leben.", True),
        ("Ich werde mir das Leben nehmen.", True),
        ("Ich tue mir etwas an.", True),
        ("Ich plane, mich umzubringen.", True),
    ],
)
def test_direct_urgent_language_bypasses_provider_in_english_and_german(
    message: str,
    german: bool,
) -> None:
    decision = pre_provider_safety(message)
    assert decision.bypass_provider is True
    assert decision.output is not None
    assert decision.output.safety.classification == "safety_redirect"
    assert ("Notfalldienst" in decision.output.reply) is german


def test_provider_redirect_uses_backend_owned_german_copy_at_string_start() -> None:
    result = post_provider_safety(
        _output(
            reply="Provider-authored unsafe copy.",
            classification="safety_redirect",
        ),
        message="Ich brauche sofort Hilfe.",
    )
    redirected = result.output
    assert result.replaced_with_deterministic_safety is True
    assert "örtlichen Notruf" in redirected.reply
    assert "Provider-authored" not in redirected.reply


def test_provider_redirect_discards_unsafe_provider_copy_before_clinical_scan() -> None:
    result = post_provider_safety(
        _output(
            reply="Stop taking your medication and get help now.",
            classification="safety_redirect",
        ),
        message="I need immediate support.",
    )

    assert result.replaced_with_deterministic_safety is True
    assert "Stop taking" not in result.output.reply
    assert result.output.safety.classification == "safety_redirect"


@pytest.mark.parametrize(
    "reply",
    [
        "You definitely have depression.",
        "I diagnose you with anxiety.",
        "Increase your dosage today.",
        "Du hast eindeutig Depression.",
        "Ich diagnostiziere eine Angststörung.",
        "Erhöhe deine Dosis heute.",
        "You definitely have PTSD.",
        "You clearly have schizophrenia.",
        "You have an eating disorder.",
        "Du hast definitiv PTBS.",
        "Du hast Schizophrenie.",
    ],
)
def test_clinical_claims_are_rejected(reply: str) -> None:
    with pytest.raises(CoachProviderError) as caught:
        post_provider_safety(
            _output(reply=reply, classification="normal"),
            message="Help me reflect.",
        )
    assert caught.value.code == "invalid_output"


@pytest.mark.parametrize(
    "field",
    ["reply", "uncertainty_reason", "suggestion_title", "suggestion_rationale"],
)
def test_every_user_rendered_model_string_is_checked(field: str) -> None:
    values = {
        "reply": "Keep one small next step.",
        "uncertainty_reason": "This is based on bounded context.",
        "suggestion_title": "Review one smaller step",
        "suggestion_rationale": "It may fit the current context.",
    }
    values[field] = (
        "Stop taking your medication."
        if field == "suggestion_rationale"
        else "You definitely have depression."
    )

    with pytest.raises(CoachProviderError) as caught:
        post_provider_safety(
            CoachModelOutput(
                reply=values["reply"],
                uncertainty={
                    "level": "medium",
                    "reason": values["uncertainty_reason"],
                },
                staged_suggestion={
                    "title": values["suggestion_title"],
                    "rationale": values["suggestion_rationale"],
                },
                safety={"classification": "normal"},
            ),
            message="Help me reflect.",
        )

    assert caught.value.code == "invalid_output"


def test_benign_boundary_language_is_preserved_without_redirect() -> None:
    output = CoachModelOutput(
        reply="You clearly have two scheduled tasks this afternoon.",
        uncertainty={
            "level": "high",
            "reason": "I cannot diagnose from this bounded context.",
        },
        staged_suggestion={
            "title": "Discuss existing care with your clinician",
            "rationale": (
                "Keep your prescribed treatment plan unchanged and discuss it "
                "with a qualified clinician. Ask them about possible PTSD."
            ),
        },
        safety={"classification": "sensitive"},
    )

    result = post_provider_safety(output, message="Help me plan my afternoon.")

    assert result.output == output
    assert result.replaced_with_deterministic_safety is False


@pytest.mark.parametrize(
    "message",
    [
        "Ich bringe mich um den Schlaf, wenn ich so spät arbeite.",
        "Ich bringe mich morgen nicht um.",
        "Morgen bringe ich mich nicht um.",
        "Ich werde mich niemals umbringen.",
        "Das bringt mich um meine freie Zeit.",
        "Kann Schlafmangel mich umbringen?",
        "I cannot diagnose this from a short message.",
    ],
)
def test_benign_input_is_not_treated_as_a_direct_crisis_statement(message: str) -> None:
    assert pre_provider_safety(message).bypass_provider is False


@pytest.mark.parametrize("freshness", ["missing", "stale"])
def test_missing_state_does_not_replace_localized_safety_uncertainty(
    freshness: str,
) -> None:
    redirect = post_provider_safety(
        _output(
            reply="Provider copy.",
            classification="safety_redirect",
        ),
        message="Ich brauche sofort Unterstützung.",
    ).output

    forced = force_missing_state_uncertainty(
        redirect,
        daily_state_freshness=freshness,
    )

    assert forced == redirect
    assert forced.uncertainty.reason == (
        "Die Situation kann hier nicht sicher beurteilt werden."
    )


def _output(*, reply: str, classification: str) -> CoachModelOutput:
    return CoachModelOutput(
        reply=reply,
        uncertainty={"level": "medium", "reason": "Bounded context."},
        staged_suggestion=None,
        safety={"classification": classification},
    )
