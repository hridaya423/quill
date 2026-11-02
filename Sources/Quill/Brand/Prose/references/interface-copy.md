# Interface copy

Use this reference for labels, buttons, links, errors, empty states, placeholders, settings, onboarding text, and other copy that appears inside a product.

Read nearby copy first. Match the product's terms, capitalization, localization conventions, and established voice. A deliberate brand voice is not a defect; change it only when it creates ambiguity, inconsistency, translation risk, or a tone the situation cannot support.

## Write the action

- Start buttons with a verb: `Save draft`, `Delete project`, `Send`.
- Make a consequential confirmation button repeat its consequence: `Delete project`, `Cancel`.
- Keep one vocabulary through a flow. Choose `Continue` or `Next`, not both for the same action.
- Make links describe their destination. Replace `Click here` and bare `Learn more` with `Read the billing docs` or `Learn more about exports`.
- Label toggles with the on-state: `Send read receipts`, not `Don't send read receipts`.
- Pick sentence case or title case per element type and apply it consistently. Sentence case is the safer default.

## Write the state

Errors sit beside the failed field, say what happened without blame, and tell the reader how to recover. Prefer `Choose a password with at least 8 characters` to `That password is too short`. Use a form-level summary only when it helps the reader find multiple failures; the field still carries its own fix.

An empty state orients the reader, explains how content gets there, and gives one clear next action. A search or filter empty state names the query and offers a way out. A placeholder is an example of format, never the only label.

System messages carry no exclamation marks and no cute interjections ("Oops", "Yay", "Whoops"). A confirmation names the object: `Invoice sent to Dana`, not `Success!`. An error says what failed and what to do next: `Couldn't send the invoice. Check Dana's email address and try again.`

Use tone by stakes: warm for success and onboarding, neutral for routine actions, calm and plain for errors, and explicit for data loss or security. In instructional copy, address `you`; in errors, prefer a direct state such as `Unable to save` over vague first-person blame.

## Review

Check every visible string against the action or state it names, then check terminology and capitalization against surrounding copy. Report one row per root cause:

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |

`HIGH` misleads or hides recovery. `MEDIUM` breaks terminology, tone, or capitalization. `LOW` is isolated polish. End with `Block` when a HIGH remains; otherwise end with `Approve` only for the inspected surface, never for unverified coverage.

Rendering and truncation belong to `craft-details`. Accessible error markup and announcements belong to the interface implementation. The prose and wording remain here.
