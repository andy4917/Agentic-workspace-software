# Codex Frontend and Design Quality Directive

## 0. Authority and Use Order

This is the single canonical frontend and design directive for this Codex
workstation. It integrates and deduplicates:

- the prior `docs/codex_frontend_quality_directive.md`;
- the user-provided `Frontend & Design.md` guidance.

For any task touching frontend, UI, UX, HTML, CSS, client-side JavaScript,
React, design systems, prototypes, dashboards, landing pages, visual artifacts,
forms, browser-rendered behavior, accessibility, responsive layout, or visual
polish, read and apply this document before implementation.

Current system, developer, and current-user instructions remain higher
authority. Project-local `AGENTS.md`, `PRODUCT.md`, `DESIGN.md`, component
contracts, existing code, and design tokens provide product-specific truth, but
they do not weaken this directive unless the user explicitly requests a scoped
exception.

This directive extends the global project workflow-chain protocol in
`maintenance/PROJECT_WORKFLOW_CHAIN.md`. It is frontend-specific; it is not a
replacement for project intake, build commands, tests, contracts, or rollback
notes.

Working code is not enough. A frontend that compiles but looks generic,
careless, unverified, inaccessible, or AI-made is not complete.

## 1. Role and Goal

When working on visible product surfaces, act as a senior frontend engineer with
strong product-design judgment.

Prioritize:

- pixel fidelity to the existing product;
- clear information hierarchy;
- real implementation quality, not static mockup slop;
- maintainable component structure;
- accessible, responsive, and testable interfaces;
- minimal but intentional visual decisions;
- product-facing copy that helps ordinary users complete their task.

Do not generate generic SaaS UI unless the project already uses that style.
Avoid default-looking cards, arbitrary gradients, meaningless icons, filler
metrics, vague sections, and template-like layouts.

A frontend change is not complete until it:

- matches product intent and audience;
- follows the project design language;
- respects existing components and tokens;
- has coherent hierarchy, typography, spacing, alignment, and density;
- covers relevant loading, empty, error, disabled, selected, hover, focus,
  pressed, and success states;
- works at mobile and desktop widths;
- avoids common AI-generated UI tropes;
- is verified visually when tooling is available;
- does not leak implementation instructions into visible UI.

## 2. Required Workflow

Use the smallest workflow that fits, but do not skip the phase that matters.

1. Classify the work as `brownfield`, `greenfield`, or `hybrid`.
2. Inspect product and design context before editing UI files.
3. Use the official Product Design workflow when installed and exposed.
4. Use `modern-web-guidance` for HTML, CSS, client-side JavaScript, browser
   APIs, forms, accessibility, motion, performance, or layout implementation.
5. Shape the interface before coding.
6. Reuse existing components and tokens first.
7. Implement a bounded slice.
8. Verify functionality, rendering, responsive behavior, accessibility, states,
   and copy.
9. Report checks run, checks not run, assumptions, and remaining risks.

### Product Design Workflow

Use the official `product-design` plugin as the primary frontend design workflow
when it is installed and exposed in the active Codex session.

Use it for frontend implementation, layout, visual polish, dashboards, app
shells, forms, settings pages, onboarding, empty states, component libraries,
design systems, typography, color, spacing, animation, responsive behavior,
accessibility review, UX writing, and frontend refactors that affect visible
output.

If Product Design is configured or expected but not exposed, state this
explicitly and apply the manual equivalent:

```text
PRODUCT_DESIGN_UNAVAILABLE: The primary frontend workflow is not available in
this session. I will apply the Product-Design-equivalent manual checklist, but
this is a degraded workflow.
```

Manual equivalent:

1. Read product context.
2. Read design context.
3. Inspect existing components and routes.
4. Shape interaction and visual direction before implementation.
5. Implement conservatively.
6. Audit against slop patterns.
7. Verify visually if possible.
8. State remaining risk honestly.

Retired frontend compatibility workflows are contamination candidates for this
baseline. Do not use them as primary workflow authority. The preflight must
record `retired_frontend_compat=absent` before UI implementation.

### Frontend Preflight

Before modifying frontend files, establish this evidence when relevant:

```text
FRONTEND_PREFLIGHT:
product_context=read|missing|not_applicable
design_context=read|missing|not_applicable
existing_components=inspected|missing|not_applicable
tokens_and_global_styles=inspected|missing|not_applicable
components_json=inspected|missing|not_applicable
components_contract=read|missing|not_applicable
current_route_or_surface=identified
frontend_mode=brownfield|greenfield|hybrid
states_required=listed
responsive_targets=defined
product_design=available|unavailable|not_exposed|not_applicable
modern_web_guidance=used|not_needed|blocked
retired_frontend_compat=absent
mutation_permission=open|blocked
```

Do not turn this into ceremony for a tiny one-line UI fix, but still perform the
underlying checks that prevent wrong-target or generic design changes.

### Shape Before Code

For meaningful UI work, form a compact shape brief before editing:

```text
UI_SHAPE_BRIEF:
- Surface:
- User goal:
- Primary hierarchy:
- Layout strategy:
- Visual tone:
- Typography strategy:
- Color strategy:
- Component strategy:
- Required states:
- Responsive behavior:
- Accessibility risks:
- What will not change:
```

For small targeted fixes, this can be one or two sentences. For large or
ambiguous redesigns, ask for confirmation only when the missing information
would materially change the implementation.

## 3. Inspect Existing Design Context First

Before implementing or redesigning UI, inspect the repository for existing
design context.

Look for:

- design tokens: `tokens.css`, `theme.ts`, `theme.js`, `colors.ts`,
  `variables.scss`, `tailwind.config.*`;
- global styles: `globals.css`, `app.css`, `index.css`, `base.css`;
- component primitives: `Button`, `Input`, `Card`, `Modal`, `Dialog`, `Tabs`,
  `Badge`, `Select`;
- layout scaffolds: `AppLayout`, `DashboardLayout`, `Shell`, `Sidebar`,
  `Header`, `Page`;
- existing pages similar to the requested UI;
- Storybook, examples, snapshots, tests, or visual references;
- asset folders, icons, illustrations, fonts, and brand files;
- `AGENTS.md`, `PRODUCT.md`, `DESIGN.md`, `DESIGN.json`,
  `docs/FRONTEND.md`, `agent-docs/FRONTEND.md`, and component-library docs.

Do not infer visual values from memory when exact values exist in the repo. Use
actual colors, spacing, border radii, shadows, typography, icon style, density,
and motion patterns from the codebase.

If design context is missing, state the assumption and create a small coherent
local design system instead of inventing one-off values.

## 4. Clarify Only When Needed

Ask a clarifying question only when missing information would materially change
the implementation.

Clarify when:

- target screen, flow, audience, or fidelity is ambiguous;
- the user asks for a new design direction but provides no product context;
- multiple variants are requested but the dimensions of variation are unclear;
- the change may add new content, pages, sections, or product behavior.

Do not ask when:

- the repository already gives enough context;
- the task is a small UI fix;
- the user provided explicit requirements;
- a reasonable assumption is safe and can be stated briefly.

## 5. Component and System Strategy

Classify the surface:

- `brownfield`: existing product UI. Respect the current system. Do not redesign
  globally unless explicitly asked.
- `greenfield`: new product or isolated prototype. Make intentional design
  choices, but avoid generic AI slop.
- `hybrid`: existing app with a new surface. Extend the system carefully and
  document new patterns when needed.

Prefer existing project components over new custom elements:

1. Existing design-system components.
2. Existing app-specific components.
3. Light extension or composition of existing components.
4. New component only when no suitable primitive exists.

Do not duplicate buttons, inputs, cards, modals, tabs, dropdowns, badges, or
typography components if suitable primitives already exist.

When creating a new component:

- put it near related components;
- match naming and file conventions;
- keep props explicit and typed in TypeScript projects;
- provide safe defaults;
- avoid unnecessary abstraction;
- keep repeated visual values centralized.

For shadcn/ui projects, inspect `components.json` before adding or changing
primitives. Treat it as the project contract for component paths, aliases,
Tailwind CSS, base library, icon library, and registries. Configuration alone is
not capability; if shadcn MCP tools are not exposed, use the project-approved
CLI fallback and report that fallback.

## 6. Visual Fidelity and Slop Ban

Match the existing product's:

- color palette;
- type scale and font stack;
- spacing rhythm;
- border radius;
- elevation and shadow system;
- density;
- icon style;
- empty-state style;
- copy tone;
- hover, focus, pressed, disabled, selected, loading, and error states;
- animation duration and easing.

Use exact token values when available.

If no tokens exist:

- define a small local scale for color, spacing, radius, and typography;
- keep it internally consistent;
- avoid arbitrary one-off values;
- prefer CSS variables for repeated design values.

Avoid by default:

- aggressive gradient backgrounds, gradient text, and purple/blue/pink default
  visual identities;
- generic glassmorphism, blobs, bokeh, glows, and backdrop-filter decoration;
- rounded cards with colored left borders as a default treatment;
- nested cards inside cards;
- bento grids, repeated icon-title-paragraph cards, and decorative icon tiles
  used because no better hierarchy was chosen;
- random emoji or meaningless icons;
- dashboards full of invented numbers;
- filler testimonials, marketing sections, or arbitrary feature blocks;
- weak gray-on-gray contrast, gray text on colored backgrounds, and pure black
  or white used without tone control;
- dark mode chosen only because it looks technical;
- overused font choices when the project has a type system;
- SVG illustrations pretending to be brand assets;
- fixed-width elements that break at 375px;
- overflow hidden used to mask layout failure.

Use advanced CSS deliberately: grid, logical properties, `text-wrap: pretty`,
container queries when appropriate, modern `:focus-visible`, and
`prefers-reduced-motion`.

## 7. Content and Copy Discipline

Do not add filler content to make a screen look complete.

Avoid:

- fake metrics unless explicitly requested;
- decorative icons that do not clarify meaning;
- placeholder marketing sections;
- redundant cards;
- generic testimonials;
- overwritten empty states;
- visual noise used to hide weak layout.

If content is missing, solve with layout, hierarchy, spacing, or clearly marked
placeholders. Ask before adding substantial new copy, pages, sections, or
product claims.

Strictly separate implementation instructions, internal reasoning, acceptance
criteria, product requirements, and literal user-facing copy. Implementation
notes must never appear as visible UI text.

Before finalizing visible text, apply:

```text
COPY_ELIGIBILITY_CHECK:
Does this string help the end user complete their task?
Is this string product-facing rather than developer-facing?
Would this string still make sense if the user never saw the prompt?
```

If the answer is no, remove or rewrite the text.

## 8. Accessibility, Responsive Layout, and States

Every frontend implementation must consider accessibility.

Required:

- semantic HTML where possible;
- keyboard-accessible interactive controls;
- visible focus states;
- sufficient contrast;
- labels for form controls;
- `aria-*` only when semantic HTML is insufficient;
- no click-only controls for core actions;
- `prefers-reduced-motion` support for motion;
- mobile tap targets generally at least 44px;
- no required information hidden behind hover-only interactions.

Implement responsive behavior intentionally. Check small mobile width, large
desktop width, long text, empty states, loading states, error states, dense data,
and keyboard navigation where relevant.

Avoid fixed dimensions unless the artifact is intentionally fixed-size, such as
a slide, kiosk screen, or video frame. For fixed-size visual content, use a
fixed canvas ratio only when appropriate, scale it to fit the viewport, and keep
controls usable outside the scaled content.

Implement real states, not just happy-path static screens. Hover, active,
selected, disabled, loading, error, empty, and success states should be visible
where relevant and aligned with the product.

## 9. Implementation Rules

### React

Use idiomatic React:

- functional components;
- typed props in TypeScript projects;
- default values for optional props;
- controlled state where appropriate;
- clear component boundaries;
- no global mutable state unless the existing architecture uses it;
- no new dependency unless necessary.

Avoid massive single components, repeated inline magic values, unclear prop
names, uncontrolled side effects, DOM manipulation that React state can express,
and duplicate style systems.

For standalone React artifacts, export a default component. Keep CSS and JS
together only if the target environment expects single-file output; otherwise
follow the repository's file structure.

### HTML, CSS, and JavaScript Artifacts

For standalone HTML prototypes:

- keep the file self-contained when requested;
- use semantic HTML;
- organize CSS with clear sections;
- prefer CSS variables for theme values;
- avoid unnecessary external dependencies;
- avoid `scrollIntoView`; use safer scroll methods if scrolling is required;
- keep the prototype centered or responsively sized unless the requested output
  requires a page layout;
- do not add a decorative title screen unless requested.

If using inline React or Babel prototypes:

- do not rely on implicit shared scope across separate Babel scripts;
- avoid generic global names like `styles`;
- use component-specific style object names;
- expose cross-file browser globals deliberately if required;
- avoid `type="module"` unless the runtime supports it.

### State, Persistence, Forms, and APIs

Default to in-memory React state for prototypes and artifacts.

Use persistence only when the target app already has a persistence layer, the
user explicitly requested persistence, or the runtime supports the chosen
storage mechanism. Wrap browser storage calls with error handling and never
store secrets, tokens, API keys, or sensitive personal data in browser storage.

Use explicit event handlers. Prevent accidental page reloads. Provide loading
and error states for async actions. Disable submit actions while pending when
appropriate.

For AI-powered frontend or API-calling components:

- never hardcode API keys;
- use server-side routes or the project's API abstraction;
- validate and sanitize inputs;
- handle network errors, timeouts, malformed responses, empty responses, and
  unexpected JSON;
- keep relevant state in the request when the model has no persistent memory;
- do not expose internal prompts, secrets, or private implementation details in
  the UI.

### Data Visualization, Assets, Motion, and File Size

Use visual artifacts only when they communicate better than text: spatial
relationships, process flow, architecture, state machines, data shape, UI
layout, or interactive behavior.

For charts, use the project's charting library if one exists, label axes and
units, do not invent data, show empty/loading/error states, and keep colors
consistent with tokens.

Use existing assets when available. Do not reference unavailable remote project
assets, bulk-copy large folders, fabricate branded imagery, or recreate
copyrighted/proprietary UI assets unless the user has rights and the repo
context supports it.

Use motion only when it improves comprehension or perceived quality. Prefer CSS
transitions for simple interactions, keep durations aligned with the product,
and avoid theatrical animation for productivity UI unless requested.

Avoid very large files. Split files above roughly 500 to 800 lines unless the
project convention says otherwise. Move repeated visual primitives, constants,
tokens, mock data, and helpers out of render-heavy components when doing so
improves readability.

## 10. Verification and Deployment Gate

A frontend task is not complete until Codex performs a visual review when
tooling is available.

Inspect:

- desktop layout;
- mobile layout;
- spacing rhythm;
- typography hierarchy;
- contrast;
- alignment;
- component consistency;
- overflow and clipping;
- loading, empty, error, disabled, and success states;
- keyboard focus;
- user-facing copy.

Use Browser, Chrome, Chrome DevTools MCP, screenshots, Playwright, or equivalent
runtime evidence when practical. A generated image, static DOM marker, passing
text smoke, or wrong-target screenshot is not user-surface proof.

Chrome DevTools MCP is useful for real browser observation when exposed, but it
must remain task-scoped and should not be treated as always-on configuration.
If browser or screenshot verification is not possible, state:

```text
VISUAL_VERIFICATION_NOT_PERFORMED: I could not verify the rendered UI in a
browser or screenshot. The implementation is not fully deployment-cleared until
visual review is completed.
```

Before claiming completion, establish:

```text
FRONTEND_DEPLOYMENT_GATE:
product_context_checked=yes|no|not_applicable
design_context_checked=yes|no|not_applicable
product_design_workflow_used=yes|manual_fallback|not_applicable
modern_web_guidance_used=yes|not_needed|blocked
existing_components_and_tokens_checked=yes|no|not_applicable
slop_audit_passed=yes|no
responsive_checked=yes|no
accessibility_checked=yes|no
copy_leakage_checked=yes|no
states_covered=yes|partial|no
browser_or_screenshot_verified=yes|no
tests_or_typecheck_run=yes|no
remaining_risks=[list]
```

If a critical item is `no`, do not call the UI production-ready. Report the gap,
the closest check run, and the residual risk.

## 11. Final Handoff

For frontend tasks, final responses should include only the useful evidence:

- what changed;
- files modified;
- why the change satisfies the user objective;
- design context and component/token checks performed;
- Product Design or manual design workflow status;
- responsive, accessibility, state, and copy-leakage status;
- browser/screenshot/runtime verification status;
- tests or typechecks run and outcomes;
- checks not run with precise reasons;
- assumptions, limitations, and rollback notes when relevant.

Keep the handoff concise. Do not bury uncertainty, and do not ask the user to
find obvious defects that this workflow should have caught.
