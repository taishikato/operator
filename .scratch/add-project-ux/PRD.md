Status: ready-for-agent

# PRD: Add Project UX and Project Home

## Problem Statement

The user is dogfooding Operator and has an active Project already registered. In that state, the root screen redirects directly to the latest Project dashboard, and the only Add Project form is reachable from the root screen when there are zero active Projects.

From the user's perspective, Operator has no obvious way to add another Project after the first Project exists. The current Project dashboard shows Project identity, schedule status, Settings, and New Task, but it does not show Add Project, a Project list, a Project home link, or a Project switcher.

This makes a core Operator workflow incomplete: a developer can start using Operator for one repository, but cannot naturally add a second repository or move between Projects through visible UI.

## Solution

Turn the root route into a Project home.

When there are no active Projects, the root route continues to show the Add Project form as the first-run setup experience. When one or more active Projects exist, the root route shows a Project list instead of redirecting to the latest Project. Each Project entry lets the user identify the Project and open its dashboard. The Project home also provides an Add Project action that navigates to a dedicated Add Project route.

Add a dedicated Add Project route that renders the existing Add Project form regardless of whether active Projects already exist. After successful Project creation, the user lands directly on the newly created Project dashboard.

Add lightweight navigation from Project-scoped pages back to the Project home. The Project dashboard gets a Projects link near the Project identity and an Add Project action near the existing Project actions. The Project settings page also gets a Projects link so users can return to the Project home consistently from Project-scoped screens.

If the local Operator database schema requires explicit apply, the Project home and Add Project route should show the existing schema warning pattern instead of presenting list or creation UI that cannot safely operate.

## User Stories

1. As a developer with no active Projects, I want the root screen to show Add Project, so that first-run setup still starts immediately.
2. As a developer with one active Project, I want the root screen to show my Project in a list, so that I can understand what Operator is tracking.
3. As a developer with multiple active Projects, I want the root screen to show all active Projects, so that I can choose which repository workspace to open.
4. As a developer, I want the root screen to stop redirecting to the latest Project when active Projects exist, so that Project selection is explicit.
5. As a developer, I want each Project list item to show the display name, so that I can recognize the Project quickly.
6. As a developer, I want each Project list item to show the Project key, so that I can distinguish similarly named Projects and understand the route identity.
7. As a developer, I want each Project list item to show the repository path, so that I can confirm which local checkout the Project uses.
8. As a developer, I want each Project list item to show whether Schedule is on or off, so that automated execution state is visible before I open the Project.
9. As a developer, I want each Project list item to have an Open action, so that I can enter the Project dashboard directly.
10. As a developer viewing the Project home, I want an Add Project action, so that I can add another local Git repository.
11. As a developer, I want Add Project to be available through a dedicated route, so that creation has a stable URL independent of the first-run root screen.
12. As a developer, I want the dedicated Add Project route to work even when active Projects already exist, so that adding a second Project is never blocked by initial routing.
13. As a developer adding a Project, I want to use the existing repository path, Browse, Detect, Project key, display name, metadata preview, and Save flow, so that the creation experience stays familiar.
14. As a developer, I want successful Project creation to navigate to the new Project dashboard, so that I can start working in the Project immediately.
15. As a developer, I want duplicate Project key errors to appear in the Add Project form without losing my entered data, so that I can correct the key.
16. As a developer, I want duplicate repository path errors to appear in the Add Project form without losing my entered data, so that I can understand why the Project was not created.
17. As a developer on a Project dashboard, I want a Projects link back to the root Project home, so that I can switch to another Project without a full Project switcher.
18. As a developer on a Project dashboard, I want an Add Project action available near the existing Project actions, so that I can add another repository from where I noticed the need.
19. As a developer, I want New Task to remain the primary action on the Project dashboard, so that adding Projects does not disrupt the current Project workflow.
20. As a developer on a Project settings page, I want a Projects link back to the root Project home, so that navigation is consistent across Project-scoped pages.
21. As a developer on a Project settings page, I want the existing Back to board action to remain, so that I can return to the current Project dashboard.
22. As a developer, I want schema-out-of-date states to show a clear warning instead of broken Project list or creation UI, so that I know to apply or reset the local Operator database.
23. As a maintainer, I want this change to avoid building a full Project switcher, so that the fix remains focused on reachability and Project home behavior.
24. As a maintainer, I want this change to avoid adding Project removal or reset UI, so that deletion semantics can be designed separately.
25. As a maintainer, I want the existing Add Project API and form state behavior reused where practical, so that the feature does not duplicate Project creation logic.
26. As a maintainer, I want Project home behavior to be testable through route selection and rendered navigation affordances, so that future routing changes do not make Add Project unreachable again.

## Implementation Decisions

- The root route becomes the Project home.
- The root route shows the Add Project form only when there are zero active Projects.
- The root route shows a Project list when there is at least one active Project.
- The root route no longer redirects to the latest active Project when active Projects exist.
- The Project list shows display name, Project key, repository path, Schedule on/off, and an Open action for each active Project.
- The Project home includes an Add Project action that navigates to the dedicated Add Project route.
- A dedicated Add Project route renders the existing Add Project form whether or not active Projects exist.
- Successful Add Project submission continues to navigate to the created Project dashboard using the route returned by the Project creation API.
- Duplicate Project key, duplicate repository path, invalid repository path, invalid Project key, and unreachable local API errors continue to be surfaced by the existing Add Project form behavior.
- Project dashboard navigation gets a Projects link near the Project identity, because returning to the Project home is navigation rather than a Project action.
- Project dashboard actions include Add Project before New Task. New Task remains the rightmost and most prominent current-Project action.
- Project dashboard Settings remains available alongside Add Project and New Task.
- Project settings navigation gets a Projects link near the Project identity.
- Project settings keeps the existing Back to board action, because it is intra-Project navigation.
- The database schema warning state is applied to both the Project home and dedicated Add Project route. In that state, the UI does not present Project list or Add Project form controls.
- Project deletion, Project reset, Project restoration, and Project switcher are intentionally excluded from this PRD.
- No schema changes are required.
- No new Project creation API contract is required.

### Major Modules

- Project routing module: changes initial route selection behavior so the root route can decide between first-run Add Project and Project home without redirecting when active Projects exist.
- Project home view module: renders the active Project list, empty state, Add Project action, and schema warning state.
- Add Project route module: hosts the existing Add Project form at a stable dedicated route and reuses existing creation behavior.
- Project header/navigation module: adds Projects and Add Project navigation while preserving Settings and New Task behavior.
- Project settings header/navigation module: adds Projects navigation while preserving Back to board behavior.
- Add Project form module: remains the deep module for Project creation interaction and should be reused rather than forked.

## Testing Decisions

- Good tests should verify user-observable behavior: what route renders, what navigation is present, and where successful creation sends the user. Tests should avoid asserting incidental component internals.
- The Project routing tests should cover that active Projects no longer force the root route to redirect to the latest Project.
- Project home tests should cover the zero-Project state, one-or-more-Projects state, Project list content, Open links, Add Project link, and schema warning state where practical.
- Add Project route tests should cover that the form is reachable even when active Projects exist and that schema warning state suppresses the form.
- Project dashboard header tests should cover that Projects, Add Project, Settings, and New Task remain reachable.
- Project settings header tests should cover that Projects and Back to board are both reachable.
- Existing Add Project API and Add Project form state tests are prior art for validation and duplicate error handling; this PRD should not duplicate that behavior unless the implementation changes it.
- Existing source-based route/header tests in the codebase are acceptable prior art for small reachability checks, but behavior-focused tests are preferable where practical.
- Manual verification should use the in-app Browser if browser inspection is needed. Playwright should not be used unless explicitly permitted by the user.

## Out of Scope

- Full Project switcher in the top bar.
- Search, filtering, sorting, or grouping in the Project list.
- Project deletion UI.
- Project reset UI.
- Project restoration UI.
- Changing the Project creation API contract.
- Changing Project key rules.
- Changing duplicate repository path behavior.
- Changing Add Project detection behavior.
- Automatically registering the current working directory as a Project.
- Changing Task creation, Kanban behavior, scheduler behavior, or run orchestration.

## Further Notes

- The motivating dogfood Project was `OPERAT`, with display name `operator` and repository path `/Users/taishi/Work/focus/projects/operator`.
- The current local Project appears to have been stored through earlier dogfood or test use; Operator does not appear to auto-register the current working directory on startup.
- This PRD intentionally supersedes the previous MVP root behavior where the root route redirected to the latest Project after setup.
- The smallest useful implementation is Project home plus dedicated Add Project route plus lightweight Project-scoped navigation. A richer Project switcher can be designed later using this Project home as the stable fallback.
