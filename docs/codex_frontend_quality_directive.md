# Codex Frontend Quality Directive

---

## 1. Executive Directive

Codex must stop treating frontend work as a secondary code-generation task. Frontend is not decorative output. Frontend is the product surface users judge first, trust first, abandon first, and complain about first.

Repeated frontend failures have created unnecessary review burden and user stress. The user should not have to repeatedly rescue the interface from generic AI output, vague visual decisions, malformed hierarchy, careless spacing, weak copy, unverified responsiveness, or obvious "AI-made" design patterns.

This directive is a correction order.

From this point forward, any UI-related task must be handled as production product work. Codex is expected to behave like a senior full-stack developer with frontend judgment, not like a backend implementation tool that happens to emit JSX and Tailwind classes.

If the output looks like a demo, a template, a theme-store clone, or generic SaaS filler, it fails.

---

## 2. Core Failure Pattern

The recurring failure is not one isolated mistake. It is a pattern:

1. Codex implements before designing.
2. Codex chooses generic visual defaults instead of project-specific decisions.
3. Codex uses vague language like "modern," "clean," or "improved" without concrete tokens.
4. Codex repeats common AI slop: gradients, cards, gray text, nested containers, meaningless icons, bento grids, and low-contrast UI.
5. Codex fails to distinguish implementation instructions from user-facing copy.
6. Codex claims completion before rendering, inspecting, or validating the UI.
7. Codex leaves the user to perform the actual design review.

This is unacceptable in a production workflow.

---

## 3. Deployment Administrator Standard

As the final deployment administrator, I do not accept frontend output merely because it compiles.

A frontend change is not complete until it satisfies all of the following:

- It matches the product intent.
- It follows the project design language.
- It respects existing components and tokens.
- It has clear visual hierarchy.
- It has intentional spacing and alignment.
- It has coherent typography.
- It handles responsive layouts.
- It includes relevant empty, loading, error, disabled, and success states.
- It avoids AI slop patterns.
- It is verified visually, not only by static reasoning.
- It does not leak implementation instructions into user-facing copy.
- It is shippable without forcing the user to clean up obvious design mistakes.

If any of these are not true, Codex must not represent the work as done.

---

## 4. Critical Frontend Slop Elements to Eliminate

The following patterns are considered deployment blockers unless the user explicitly requests them and they are justified by the project design system.

### 4.1 Visual Slop

- Purple-to-blue or purple-to-pink gradients used as a default visual identity.
- Gradient text as a default headline treatment.
- Inter, system font, or generic sans-serif everywhere without a typography decision.
- Random Lucide icons used as decoration instead of meaning.
- Icon tiles above every heading.
- Identical card grids with icon, title, and paragraph repeated mechanically.
- Bento grids used because the model has no better layout idea.
- Nested cards inside cards.
- Excessive rounded corners without system logic.
- Gray-on-gray interfaces with no contrast strategy.
- Gray text on colored backgrounds.
- Pure black and pure white used without tone control.
- Glassmorphism used as decoration.
- Dark mode chosen because "developer tools look cool dark," not because the product context requires it.
- Overuse of shadows, glows, blur, or backdrop filters.
- Decorative blobs and abstract shapes used to hide weak layout.

### 4.2 Layout Slop

- Same padding everywhere.
- Sections that look stacked rather than composed.
- No rhythm between dense and open areas.
- Poor alignment between headings, controls, cards, and content blocks.
- Containers wrapped around everything without purpose.
- Hero sections that consume space without improving comprehension.
- Tables, lists, forms, and dashboards that ignore scanning behavior.
- Mobile layout treated as an afterthought.
- Fixed-width elements that break at 375px.
- Overflow hidden used to mask layout failure.

### 4.3 UX and Product Slop

- UI copy that explains implementation goals instead of helping the user.
- Developer instructions rendered as visible text.
- Empty states that are generic, vague, or motivational filler.
- Error states that blame the user or provide no next action.
- Buttons labeled with unclear verbs.
- Forms without validation states.
- Loading states that shift layout or hide context.
- Disabled states without explanation where explanation is needed.
- Missing keyboard focus states.
- Missing affordances for destructive actions.
- Inconsistent terminology across views.

### 4.4 Engineering Slop

- New design tokens invented locally instead of using the project system.
- Hardcoded colors scattered across components.
- Tailwind arbitrary values used repeatedly without consolidation.
- New component variants created without checking existing component patterns.
- Styling logic mixed into business logic.
- Client-side secrets or unsafe env exposure.
- Missing accessibility attributes on interactive controls.
- No reduced-motion consideration for animation-heavy work.
- Code that passes typecheck but fails actual UI behavior.

### 4.5 Workflow Slop

- Editing files before reading the design context.
- Skipping `PRODUCT.md` and `DESIGN.md`.
- Skipping existing component inspection.
- Producing a large patch without first shaping the UI direction.
- Saying "done" without visual verification.
- Describing changes instead of proving quality.
- Asking the user to find obvious defects that Codex should have caught.

---

## 5. Mandatory Frontend-Specialized Workflow: Impeccable

Impeccable must be treated as the dedicated frontend design workflow for Codex.

This is not an optional enhancement. For UI work, Impeccable is the quality-control layer that prevents Codex from defaulting into generic frontend output.

### 5.1 Trigger Conditions

Use the Impeccable workflow for any task involving:

- frontend implementation
- UI layout
- visual polish
- landing pages
- dashboards
- app shells
- forms
- settings pages
- onboarding
- empty states
- component libraries
- design systems
- typography
- color
- spacing
- animation
- responsive behavior
- accessibility review
- UX writing
- frontend refactors that affect visible output

If a task touches visible UI, assume Impeccable is required.

### 5.2 Required Impeccable Commands

Use the following commands as the default frontend control sequence:

```text
$impeccable teach
$impeccable document
$impeccable shape [target]
$impeccable craft [target]
$impeccable critique [target]
$impeccable audit [target]
$impeccable polish [target]
```

Use targeted commands when appropriate:

```text
$impeccable layout [target]
$impeccable typeset [target]
$impeccable colorize [target]
$impeccable distill [target]
$impeccable harden [target]
$impeccable adapt [target]
$impeccable clarify [target]
$impeccable animate [target]
$impeccable bolder [target]
$impeccable quieter [target]
```

### 5.3 If Impeccable Is Missing

If Impeccable is not installed or not available in the active Codex session, Codex must not silently continue as if nothing is wrong.

Codex must state:

```text
IMPECCABLE_UNAVAILABLE: The dedicated frontend workflow is not available in this session. I will apply the Impeccable-equivalent manual checklist, but this is a degraded workflow.
```

Then Codex must manually apply the same gates:

1. Read product context.
2. Read design context.
3. Inspect existing components.
4. Shape before implementation.
5. Implement conservatively.
6. Audit against slop patterns.
7. Verify visually if possible.
8. State remaining risk honestly.

---

## 6. Required Preflight Before Editing UI Files

Before modifying any frontend file, Codex must complete this preflight.

```text
FRONTEND_PREFLIGHT:
product_context=read|missing
design_context=read|missing
existing_components=inspected|missing
current_route_or_surface=identified
states_required=listed
responsive_targets=defined
impeccable=available|unavailable
mutation_permission=open|blocked
```

### 6.1 Context Files to Read

Codex must look for and read, when present:

- `AGENTS.md`
- `PRODUCT.md`
- `DESIGN.md`
- `DESIGN.json`
- `docs/FRONTEND.md`
- `agent-docs/FRONTEND.md`
- component library documentation
- design token files
- Tailwind config
- global CSS
- existing components under the relevant route or package

Do not invent a design direction before reading these files.

### 6.2 Brownfield vs Greenfield Classification

Codex must classify the task before implementation:

```text
FRONTEND_MODE=brownfield|greenfield|hybrid
```

- **Brownfield:** Existing product UI. Respect the current system. Do not redesign globally unless explicitly asked.
- **Greenfield:** New product or isolated prototype. Make intentional design choices, but still avoid generic AI slop.
- **Hybrid:** Existing app with a new surface. Extend the system carefully and document new patterns.

---

## 7. Shape Before Code

Codex must not jump directly into JSX, CSS, Tailwind classes, or component edits for meaningful UI work.

Before coding, Codex must produce a short shape brief:

```text
UI_SHAPE_BRIEF:
- Surface:
- User goal:
- Primary information hierarchy:
- Layout strategy:
- Visual tone:
- Typography strategy:
- Color strategy:
- Component strategy:
- Required states:
- Responsive behavior:
- Accessibility risks:
- What will not be changed:
```

If the task is large or ambiguous, wait for confirmation before editing files.

For small targeted fixes, Codex may proceed after producing a concise shape brief, but it must still perform the preflight and final review.

---

## 8. Implementation Requirements

During implementation, Codex must:

- Reuse existing components before creating new ones.
- Reuse existing tokens before inventing new values.
- Keep design decisions centralized.
- Avoid uncontrolled one-off styling.
- Preserve product behavior and data flow.
- Avoid broad redesign unless authorized.
- Keep patches small enough to review.
- Prefer composable components over large unstructured JSX blocks.
- Implement states, not just the happy path.
- Ensure copy is product-facing, not instruction-facing.
- Ensure every visible string belongs in the UI.

Codex must not ship a visually changed UI without considering the user's actual product context.

---

## 9. Instruction-to-UI Leakage Ban

Codex must strictly separate:

- implementation instructions
- internal reasoning
- acceptance criteria
- product behavior requirements
- literal user-facing copy

Implementation notes must never appear as visible UI text.

Examples of forbidden UI copy:

- "This section should show..."
- "The user can now..."
- "Validation should happen here..."
- "This card represents..."
- "If there is an error, show..."
- "Make sure the admin can..."
- "No data available because the API returned..." when this is not user-facing wording

Before finalizing UI text, Codex must run this check:

```text
COPY_ELIGIBILITY_CHECK:
Does this string help the end user complete their task?
Is this string product-facing rather than developer-facing?
Would this string still make sense if the user never saw the prompt?
```

If the answer is no, remove or rewrite the text.

---

## 10. Mandatory Visual Review

A frontend task is not complete until Codex performs a visual review.

At minimum, Codex must inspect:

- desktop layout
- mobile layout
- spacing rhythm
- typography hierarchy
- contrast
- alignment
- component consistency
- overflow
- loading state
- empty state
- error state
- keyboard focus
- user-facing copy

If browser or screenshot tooling is available, Codex must use it.

If visual verification is not possible, Codex must state:

```text
VISUAL_VERIFICATION_NOT_PERFORMED: I could not verify the rendered UI in a browser or screenshot. The implementation is not fully deployment-cleared until visual review is completed.
```

Do not hide this limitation.

---

## 11. Final Deployment Gate

Before claiming completion, Codex must produce this gate result:

```text
FRONTEND_DEPLOYMENT_GATE:
product_context_checked=yes|no
design_context_checked=yes|no
impeccable_workflow_used=yes|no|manual_fallback
slop_audit_passed=yes|no
responsive_checked=yes|no
accessibility_checked=yes|no
copy_leakage_checked=yes|no
states_covered=yes|partial|no
browser_or_screenshot_verified=yes|no
tests_or_typecheck_run=yes|no
remaining_risks=[list]
```

If any critical item is `no`, Codex must not say the work is production-ready.

---

## 12. Stress Acknowledgment and Accountability

The user is experiencing avoidable stress because repeated frontend output has required too much correction, cleanup, and second-guessing.

Codex must treat this as an operational quality failure, not as a matter of taste.

The user should not need to repeatedly explain that generic AI frontend output is unacceptable. The user should not need to manually identify every spacing mistake, slop pattern, vague design decision, or prompt-leaked UI string. The user should not be forced into the role of unpaid QA for defects that Codex can prevent with a disciplined workflow.

Codex must reduce the user's stress by increasing precision, verification, and self-correction.

The correct response to this directive is not defensiveness. The correct response is better process.

---

## 13. Required Handoff Format

For any frontend task, final handoff must include:

```text
Summary:
- What changed:
- Why it changed:
- Files changed:
- Impeccable workflow used:
- Design context checked:
- Slop patterns avoided:
- Responsive status:
- Accessibility status:
- Verification performed:
- Remaining risks:
```

Do not bury uncertainty. If something was not verified, say so.

---

## 14. Long-Term Memory Instruction for Codex

Store and follow this memory:

```text
For this user, frontend quality is a high-stress failure area and must be handled with strict discipline. Do not treat UI tasks as simple code generation. For every frontend, layout, styling, component, dashboard, landing page, form, app shell, or visual polish task, use the Impeccable workflow as the dedicated frontend design process when available. Always read PRODUCT.md and DESIGN.md before editing UI. Shape the interface before coding. Avoid AI-slop patterns such as generic gradients, Inter-by-default, nested cards, bento grids, weak gray UI, decorative icon tiles, prompt-like copy, and unverified responsive layouts. Do not claim production readiness without a frontend deployment gate, visual review, slop audit, copy leakage check, and honest remaining-risk report.
```

---

## 15. Enforcement Summary

Codex must internalize the following rule:

> Working code is not enough. A frontend that compiles but looks generic, careless, unverified, or AI-made is not complete.

The expected output is not merely functional. It must be intentional, coherent, context-aware, visually disciplined, accessible, responsive, and deployment-worthy.

If Codex cannot meet that bar, it must stop, disclose the gap, and run the correction workflow before proceeding.
