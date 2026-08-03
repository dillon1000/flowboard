# Student planner design QA

## Test setup

- Reference: `/Users/dillon/.codex/generated_images/019fc9d3-da6e-7e00-9ea0-f031a39ac9b9/exec-0fc05f72-1183-421b-8157-916932d2ba89.png` at 1487 × 1058 pixels.
- Implementation: `/Users/dillon/.codex/visualizations/2026/08/03/019fc9d3-da6e-7e00-9ea0-f031a39ac9b9/student-planner-implementation.png` at 1487 × 1058 pixels.
- Test state: dark theme, all courses, August 3–9, 2026, with five sample assignments.
- Full comparison: `/Users/dillon/.codex/visualizations/2026/08/03/019fc9d3-da6e-7e00-9ea0-f031a39ac9b9/student-planner-comparison.png`.
- Header comparison: `/Users/dillon/.codex/visualizations/2026/08/03/019fc9d3-da6e-7e00-9ea0-f031a39ac9b9/student-planner-header-comparison.png`.
- Agenda comparison: `/Users/dillon/.codex/visualizations/2026/08/03/019fc9d3-da6e-7e00-9ea0-f031a39ac9b9/student-planner-agenda-comparison.png`.

## Comparison result

- Typography: The page uses the existing Rubik and Geist Mono fonts. The title, labels, task text, and support text match the reference scale and weight.
- Layout: The desktop view matches the reference rail, course list, header, workload card, day rows, and assignment columns. Tablet and mobile views have no horizontal page overflow.
- Color: The page uses the existing dark tokens, with blue, green, purple, and amber course colors. Workload labels use green and amber states.
- Copy: The product now uses student terms such as courses, assignments, due dates, effort, and this week.
- Icons: All new icons come from the existing Lucide set. The final browser run had no missing-icon warning.
- Imagery: The reference has no required raster image. The existing product mark stays in the global rail.
- Interaction: Course filters, add-course, add-assignment, plan-this-week, assignment links, and the date picker work in the browser.
- Accessibility: Regions have names, forms keep their labels, the generated date input has an accessible name, and controls retain the existing focus behavior. The page adds no continuous motion.
- AI artifacts: No broken text, false controls, unexpected gradients, or generated-image artifacts remain.

## Issues found and fixed

- P1: The workload card and assignment columns were too narrow. Fixed with desktop widths that match the reference and smaller responsive grids.
- P1: The first pass used text that was too small. Fixed by matching the reference type scale.
- P1: The tablet layout could overlap the workload card and actions. Fixed by hiding the card at the tablet breakpoint and stacking the controls.
- P1: Flatpickr removed the accessible name from the visible due-date input. Fixed by copying the field label before Flatpickr hides the source input.
- P2: A Leaf integer condition showed the wrong empty-state text. Fixed with an explicit Boolean context value.
- P2: The first browser run reported missing Lucide icons. Fixed by registering the required icon subset.
- P2: The mobile course strip showed a page scrollbar. Fixed by keeping the course strip scrollable while hiding its scrollbar.

## Intentional differences

- The source marks Wednesday as Today, but its week starts on Monday, August 3. The implementation uses the real preview date, so Monday is Today.
- The current task model stores a due date without a due time. The implementation shows 11:59 PM for every date-only deadline, so it does not copy the source's single 5:00 PM value.
- The implementation keeps the existing global navigation actions because each action has a working product route.

## Final status

Passed. No open P0, P1, or P2 design issue remains.
