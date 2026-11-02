# UI states — shared copy rule IDs

The authored copy rules other skills cite by ID. `product-design` decides which
rule governs a surface and routes the wording here; this file owns how the rule
is worded. For the surrounding copy practice (matching vocabulary, tone by
stakes, review table), see `interface-copy.md`.

| ID | Rule |
|----|------|
| `rule/destructive-names-action` | Destructive and primary CTAs use Verb plus Noun naming the object (`Delete project`), never `Confirm`/`OK`/`Yes`. |
| `rule/no-confirm-ok-labels` | No bare `Confirm`, `OK`, `Yes`, or `Submit` on a consequential action. `Save`, `Cancel`, and `Close` are exempt: they name their own outcome. |
| `rule/canonical-verb` | One canonical verb per operation across the product. The verb carries the consequence: `Delete` permanent, `Remove` detach, `Archive` recoverable, `Cancel` abandon in-progress, `Discard` drop unsaved edits. |
| `rule/error-states-recovery` | An error states what happened, why when known, and the recovery action; never raw exception text. |
| `rule/success-state-specific` | A success message confirms in past tense what happened to which object, proportional to the action. |
| `rule/empty-state-action` | An empty state names the object and offers the first action; no dead ends. |
| `rule/loading-state-specific` | Prefer specific loading copy over a bare `Loading...` when the target is known. |
| `rule/permission-benefit-first` | A permission request states the user benefit before the ask, in context of first use. |
| `rule/reads-without-seeing` | Copy works when heard: errors read sensibly after the field label, links name the destination, no directional words. |
