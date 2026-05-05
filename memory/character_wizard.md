---
name: Character Registration Wizard
description: Multi-step wizard for character registration and verification, modal ID scheme, wizard_context pattern, OAuth intercept plan
type: project
---

Replaced the old `register_character_modal` with a unified wizard in `app/views/character_registrations/wizard/`.

**Why:** Users were hitting a dead-end "no verified characters" error after OAuth registration. Goal is to guide through register→verify in one flow, and reuse it as an OAuth intercept.

**How to apply:** Any work touching character registration or verification flows should use the wizard components.

## Stable modal ID
`character_wizard_modal` — single turbo-frame ID for both registration and standalone verification flows.

## Key files
- `wizard/_container.html.erb` — outer turbo-frame + Bootstrap modal shell
- `wizard/_step_indicator.html.erb` — reusable progress bar (locals: `steps` Array, `current` Integer)
- `wizard/_search_step`, `_confirm_step`, `_verify_step`, `_pending_step` — the four active steps
- `wizard/_verification_success`, `_verification_retry`, `_verification_failed_*`, `_generic_failure` — job-broadcast result partials (render `modal-body` + `modal-footer` only; header persists above job-target div)
- `CharacterRegistrationsHelper` — `WIZARD_STEPS`, `WIZARD_DONE_STEP`, `WIZARD_VERIFY_STEP` constants + helper methods

## wizard_context flow
Passed as hidden field `wizard_context` through every form. Values: `:register` (3 steps) or `:verify` (2 steps).
- `CharacterRegistrationsController` sets `@wizard_context = params[:wizard_context]`
- `CharacterRegistrations::VerificationsController` sets same; has `helper CharacterRegistrationsHelper` to access helper methods in views

## Pending step / job broadcast threading
`_pending_step` renders `turbo_stream_from` + step header OUTSIDE the job-target div:
```
character_wizard_modal-content
  turbo_stream_from (subscription)
  modal-header with step indicator  ← persists through job broadcasts
  div#character-registration-job:JOB_ID:content  ← replaced by job
    modal-body + modal-footer
```

## OAuth intercept (not yet built)
Plan: store OAuth return URL in session, detect it in `after_sign_up_path_for`, pass `wizard_context: :register` + `return_to:` param. On `_verification_success`, check for return URL and show "Continue to App" button instead of "Done!".
