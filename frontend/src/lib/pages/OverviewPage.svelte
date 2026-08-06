<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { scrollFades } from '$lib/actions/scrollFades';
  import CreateBoardDialog from '$lib/components/CreateBoardDialog.svelte';
  import DatePicker from '$lib/components/DatePicker.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import TimePicker from '$lib/components/TimePicker.svelte';
  import type {
    AutoPlanStudySessionsResponse,
    CommonPageContext,
    OverviewPageContext,
    RepairStudyWeekResponse,
    StudyAssignmentContext,
    StudyCalendarConflict,
    StudyCourseContext,
    StudyEstimatePreset,
    StudyEstimateInboxItemContext,
    StudyOnboardingStepContext,
    StudyRecurringCommitment,
    StudySettingsContext,
    StudyDayContext,
    StudyPlanCandidateContext,
    TaskResponse
  } from '$lib/types';
  import { previewFromAssignment, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';
  import {
    ArrowCircleUpRightIcon as OpenAssignment,
    CalendarDotsIcon as CalendarDays,
    ClockIcon as Clock3,
    FileTextIcon as FileText,
    MinusIcon as Minus,
    PlusIcon as Plus,
    StackIcon as Layers,
    StrategyIcon as Strategy,
    TrashIcon as Trash2,
    XIcon as X
  } from 'phosphor-svelte';

  const weekdays = [
    { key: 'monday', label: 'Mon', index: 1 },
    { key: 'tuesday', label: 'Tue', index: 2 },
    { key: 'wednesday', label: 'Wed', index: 3 },
    { key: 'thursday', label: 'Thu', index: 4 },
    { key: 'friday', label: 'Fri', index: 5 },
    { key: 'saturday', label: 'Sat', index: 6 },
    { key: 'sunday', label: 'Sun', index: 7 }
  ] as const;

  let { overview, common } = $props<{ overview: OverviewPageContext; common: CommonPageContext }>();
  const initialOverview = $state.snapshot((() => overview)());
  let createBoardOpen = $state(false);
  let createTaskOpen = $state(false);
  let planOpen = $state(false);
  let availabilityOpen = $state(false);
  let estimatesOpen = $state(false);
  let completeOpen = $state(false);
  let moveOpen = $state(false);
  let planSelection = $state('');
  let planMinutes = $state(60);
  let pendingCount = $state(0);
  const pending = $derived(pendingCount > 0);
  let requestError = $state('');
  let expandedDays = $state<Record<string, boolean>>({});
  let activeSession = $state<StudyAssignmentContext | null>(null);
  let actualMinutes = $state(30);
  let moveDate = $state('');

  let weekdayCapacityMinutes = $state<Record<string, number>>({ ...initialOverview.studySettings.weekdayCapacityMinutes });
  let blockedDates = $state<string[]>([...initialOverview.studySettings.blockedDates]);
  let recurringCommitments = $state<StudyRecurringCommitment[]>(initialOverview.studySettings.recurringCommitments.map((item: StudyRecurringCommitment) => ({ ...item, weekdays: [...item.weekdays] })));
  let calendarConflicts = $state<StudyCalendarConflict[]>(initialOverview.studySettings.calendarConflicts.map((item: StudyCalendarConflict) => ({ ...item })));
  let estimatePresets = $state<StudyEstimatePreset[]>(initialOverview.studySettings.estimatePresets.map((item: StudyEstimatePreset) => ({ ...item, keywords: [...item.keywords] })));
  let estimateValues = $state<Record<string, number>>(Object.fromEntries(initialOverview.estimationInbox.map((item: StudyEstimateInboxItemContext) => [item.id, item.suggestedMinutes])));
  let blockedDateDraft = $state('');
  let commitmentTitle = $state('');
  let commitmentKind = $state<'class' | 'work'>('class');
  let commitmentWeekdays = $state<number[]>([]);
  let commitmentStart = $state('09:00');
  let commitmentEnd = $state('10:00');
  let conflictTitle = $state('');
  let conflictDate = $state('');
  let conflictStart = $state('09:00');
  let conflictEnd = $state('10:00');

  const courseOptions = $derived<SelectMenuOption[]>(
    overview.courseFilters.map((course: StudyCourseContext) => ({ value: course.id, label: course.name }))
  );
  const planOptions = $derived<SelectMenuOption[]>(
    overview.planCandidates.map((assignment: StudyPlanCandidateContext) => ({
      value: assignment.id,
      label: `${assignment.title} - ${assignment.courseName}`
    }))
  );
  const deadlineCount = $derived(overview.days.reduce((total: number, day: StudyDayContext) => total + day.assignmentCount, 0));
  const selectedCourseID = $derived(overview.courseFilters.find((course: StudyCourseContext) => course.isSelected)?.id ?? null);
  const todayDateInput = $derived(overview.days.find((day: StudyDayContext) => day.isToday)?.dateInput ?? overview.days[0]?.dateInput ?? '');
  const planRemainingMinutes = $derived(overview.planCandidates.find((candidate: StudyPlanCandidateContext) => candidate.id === planSelection)?.remainingMinutes ?? 1_440);
  const plannedMinutes = $derived(overview.days.reduce((total: number, day: StudyDayContext) => total + day.workloadMinutes, 0));
  const weeklyCapacity = $derived(Object.values(weekdayCapacityMinutes).reduce((total, minutes) => total + Number(minutes), 0));
  const currentOnboardingStep = $derived(overview.onboarding.steps.find((step: StudyOnboardingStepContext) => step.isCurrent));
  const unplannedPreview = $derived<StudyPlanCandidateContext[]>(overview.planCandidates.slice(0, 3));
  const busiestDay = $derived.by<StudyDayContext | null>(() => {
    let busiest: StudyDayContext | null = null;
    for (const day of overview.days) {
      if (!busiest || day.workloadMinutes > busiest.workloadMinutes) busiest = day;
    }
    return busiest && busiest.workloadMinutes > 0 ? busiest : null;
  });
  const weekState = $derived.by(() => {
    if (overview.recovery.hasIssues) return `${overview.recovery.summary} Repair the week before adding more work.`;
    if (overview.hasUnestimatedAssignments) return `${overview.unestimatedAssignmentCount} ${overview.unestimatedAssignmentCount === 1 ? 'assignment needs' : 'assignments need'} a time estimate before the plan is complete.`;
    if (!busiestDay && overview.hasPlanCandidates) return `${overview.unplannedFocusCount} ${overview.unplannedFocusCount === 1 ? 'assignment needs' : 'assignments need'} study time.`;
    if (!busiestDay) return 'Nothing needs planning this week.';
    return `Your busiest day is ${busiestDay.weekdayLabel} at ${durationLabel(busiestDay.workloadMinutes)} of ${durationLabel(busiestDay.availableMinutes)} available.`;
  });

  function durationLabel(minutes: number): string {
    if (minutes === 0) return '0m';
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder === 0 ? `${hours}h` : `${hours}h ${remainder}m`;
  }

  function estimateMinutes(value: FormDataEntryValue | null): number | null {
    const minutes = Number(value);
    return Number.isInteger(minutes) && minutes > 0 ? minutes : null;
  }

  function toggleDay(dateLabel: string): void {
    const update = () => (expandedDays[dateLabel] = expandedDays[dateLabel] === false);
    const transitionDocument = document as Document & { startViewTransition?: (callback: () => void) => unknown };
    if (matchMedia('(prefers-reduced-motion: reduce)').matches || !transitionDocument.startViewTransition) {
      update();
      return;
    }
    transitionDocument.startViewTransition(update);
  }

  function loadClass(day: StudyDayContext): string {
    if (day.isBlocked) return 'blocked';
    if (day.unestimatedAssignmentCount > 0) return 'needs-estimates';
    if (day.isOverloaded) return 'overloaded';
    return day.workloadMinutes > 0 ? 'planned' : 'empty';
  }

  function loadLabel(day: StudyDayContext): string {
    if (day.isBlocked) return 'Blocked';
    if (day.unestimatedAssignmentCount > 0) return 'Needs estimates';
    if (day.isOverloaded) return 'Over capacity';
    return day.workloadMinutes > 0 ? 'Fits' : 'Open';
  }

  function loadPercent(day: StudyDayContext): number {
    if (day.workloadMinutes === 0) return day.unestimatedAssignmentCount > 0 ? 20 : 0;
    if (day.availableMinutes === 0) return 100;
    return Math.max(7, Math.min(100, (day.workloadMinutes / day.availableMinutes) * 100));
  }

  function openPlan(assignmentID: string): void {
    planSelection = assignmentID;
    const assignment = overview.planCandidates.find((candidate: StudyPlanCandidateContext) => candidate.id === assignmentID);
    planMinutes = Math.min(60, assignment?.remainingMinutes ?? 60);
    planOpen = true;
  }

  function selectPlan(assignmentID: string): void {
    planSelection = assignmentID;
    const assignment = overview.planCandidates.find((candidate: StudyPlanCandidateContext) => candidate.id === assignmentID);
    planMinutes = Math.min(60, assignment?.remainingMinutes ?? 60);
  }

  function openComplete(session: StudyAssignmentContext): void {
    activeSession = session;
    actualMinutes = Math.max(1, session.estimatedMinutes);
    requestError = '';
    completeOpen = true;
  }

  function openMove(session: StudyAssignmentContext): void {
    activeSession = session;
    const todayIndex = overview.days.findIndex((day: StudyDayContext) => day.isToday);
    moveDate = overview.days[todayIndex + 1]?.dateInput ?? todayDateInput;
    requestError = '';
    moveOpen = true;
  }

  function addBlockedDate(): void {
    if (!blockedDateDraft || blockedDates.includes(blockedDateDraft)) return;
    blockedDates = [...blockedDates, blockedDateDraft].sort();
    blockedDateDraft = '';
  }

  function toggleCommitmentWeekday(index: number, checked: boolean): void {
    commitmentWeekdays = checked
      ? [...new Set([...commitmentWeekdays, index])].sort()
      : commitmentWeekdays.filter((value) => value !== index);
  }

  function addCommitment(): void {
    if (!commitmentTitle.trim() || commitmentWeekdays.length === 0 || commitmentEnd <= commitmentStart) {
      requestError = 'Add a title, at least one weekday, and an end time after the start time.';
      return;
    }
    recurringCommitments = [...recurringCommitments, {
      id: crypto.randomUUID(),
      title: commitmentTitle.trim(),
      kind: commitmentKind,
      weekdays: [...commitmentWeekdays],
      startTime: commitmentStart,
      endTime: commitmentEnd
    }];
    commitmentTitle = '';
    commitmentWeekdays = [];
    requestError = '';
  }

  function addConflict(): void {
    if (!conflictTitle.trim() || !conflictDate || conflictEnd <= conflictStart) {
      requestError = 'Add a conflict date and an end time after the start time.';
      return;
    }
    calendarConflicts = [...calendarConflicts, {
      id: crypto.randomUUID(),
      title: conflictTitle.trim(),
      date: conflictDate,
      startTime: conflictStart,
      endTime: conflictEnd
    }];
    conflictTitle = '';
    conflictDate = '';
    requestError = '';
  }

  async function persistSettings(overrides: Partial<Pick<StudySettingsContext, 'timeZoneConfirmed' | 'availabilityConfigured'>> = {}): Promise<void> {
    await api('/api/v1/study-settings', {
      method: 'PUT',
      body: JSON.stringify({
        weekdayCapacityMinutes: Object.fromEntries(Object.entries(weekdayCapacityMinutes).map(([key, value]) => [key, Number(value)])),
        blockedDates,
        recurringCommitments,
        calendarConflicts,
        estimatePresets: estimatePresets.map((preset) => ({ ...preset, minutes: Number(preset.minutes) })),
        timeZoneConfirmed: overrides.timeZoneConfirmed ?? overview.studySettings.timeZoneConfirmed,
        availabilityConfigured: overrides.availabilityConfigured ?? overview.studySettings.availabilityConfigured
      })
    });
  }

  async function confirmTimeZone(): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      await api('/api/v1/auth/me', {
        method: 'PATCH',
        body: JSON.stringify({ name: common.userName, timeZone })
      });
      await persistSettings({ timeZoneConfirmed: true });
      await refreshAll();
      showToast(`Time zone set to ${timeZone}`);
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function saveAvailability(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    pendingCount += 1;
    requestError = '';
    try {
      await persistSettings({ availabilityConfigured: true });
      availabilityOpen = false;
      await refreshAll();
      showToast('Availability saved');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  function applyPreset(taskID: string, presetID: string): void {
    const preset = estimatePresets.find((item) => item.id === presetID);
    if (preset) estimateValues[taskID] = Number(preset.minutes);
  }

  async function saveEstimates(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const estimates = overview.estimationInbox.map((item: StudyEstimateInboxItemContext) => ({ taskID: item.id, estimatedMinutes: Number(estimateValues[item.id]) }));
    if (estimates.some((item: { taskID: string; estimatedMinutes: number }) => !Number.isInteger(item.estimatedMinutes) || item.estimatedMinutes < 5 || item.estimatedMinutes > 1_440)) {
      requestError = 'Set every estimate between 5 and 1440 minutes.';
      return;
    }
    pendingCount += 1;
    requestError = '';
    try {
      await api('/api/v1/study-settings/estimates', {
        method: 'POST',
        body: JSON.stringify({ estimates, estimatePresets })
      });
      estimatesOpen = false;
      await refreshAll();
      showToast(`${estimates.length} ${estimates.length === 1 ? 'estimate' : 'estimates'} saved`);
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function createAssignment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const dueDate = String(data.get('dueAt') ?? '');
    pendingCount += 1;
    requestError = '';
    try {
      await api<TaskResponse>('/api/v1/tasks', {
        method: 'POST',
        body: JSON.stringify({
          boardID: String(data.get('boardID') ?? overview.defaultCourseID),
          title: String(data.get('title') ?? ''),
          description: String(data.get('description') ?? '') || null,
          labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6),
          dueAt: dueDate ? `${dueDate}T00:00:00Z` : null,
          dueTime: dueDate ? String(data.get('dueTime') ?? '') || null : null,
          estimatedMinutes: estimateMinutes(data.get('estimatedMinutes'))
        })
      });
      form.reset();
      createTaskOpen = false;
      await refreshAll();
      showToast('Assignment added');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function planAssignment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const taskID = String(data.get('taskID') ?? '');
    const focusDate = String(data.get('focusDate') ?? '');
    const planned = Number(data.get('plannedMinutes'));
    if (!taskID || !focusDate) return;
    pendingCount += 1;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${taskID}/study-sessions`, { method: 'POST', body: JSON.stringify({ scheduledDate: focusDate, plannedMinutes: planned }) });
      planOpen = false;
      await refreshAll();
      showToast('Study session added');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function autoPlanWeek(): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      const result = await api<AutoPlanStudySessionsResponse>('/api/v1/study-sessions/plan', {
        method: 'POST',
        body: JSON.stringify({ courseID: selectedCourseID })
      });
      await refreshAll();
      if (result.plannedMinutes === 0) showToast('The available work is already planned');
      else if (result.remainingMinutes > 0) showToast(`Planned ${durationLabel(result.plannedMinutes)}; ${durationLabel(result.remainingMinutes)} still needs room`);
      else showToast(`Planned ${durationLabel(result.plannedMinutes)} across the week`);
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function repairWeek(): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      const result = await api<RepairStudyWeekResponse>('/api/v1/study-sessions/repair', { method: 'POST' });
      await refreshAll();
      showToast(result.remainingMinutes > 0
        ? `Repaired ${result.repairedSessionCount} blocks; ${durationLabel(result.remainingMinutes)} still needs room`
        : `Repaired ${result.repairedSessionCount} ${result.repairedSessionCount === 1 ? 'block' : 'blocks'}`);
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function completeSession(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!activeSession) return;
    pendingCount += 1;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${activeSession.studySessionID}/complete`, { method: 'POST', body: JSON.stringify({ actualMinutes: Number(actualMinutes) }) });
      completeOpen = false;
      await refreshAll();
      showToast('Study session completed');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function moveSession(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!activeSession || !moveDate) return;
    pendingCount += 1;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${activeSession.studySessionID}`, { method: 'PATCH', body: JSON.stringify({ scheduledDate: moveDate }) });
      moveOpen = false;
      await refreshAll();
      showToast('Study session moved');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function skipSession(sessionID: string): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${sessionID}/skip`, { method: 'POST' });
      await refreshAll();
      showToast('Study session skipped');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function deleteStudySession(sessionID: string): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${sessionID}`, { method: 'DELETE' });
      await refreshAll();
      showToast('Study session removed');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  function runOnboardingStep(): void {
    switch (overview.onboarding.nextStepKey) {
      case 'timezone': void confirmTimeZone(); break;
      case 'availability': availabilityOpen = true; break;
      case 'estimates': estimatesOpen = true; break;
      case 'plan': void autoPlanWeek(); break;
    }
  }
</script>

<div class="page study-page">
  <div class="study-planner">
    <aside class="study-course-panel" aria-label="This week and courses">
      <div class="study-panel-heading"><h1>Week</h1><span>{overview.weekLabel}</span></div>
      <dl class="study-week-stats">
        <div><dt>Due</dt><dd>{deadlineCount}</dd></div>
        <div><dt>Planned</dt><dd>{durationLabel(plannedMinutes)}</dd></div>
        <div><dt>Streak</dt><dd>{overview.studyStreakDays}d</dd></div>
      </dl>
      <div class="study-course-heading"><h2>Courses</h2><button class="icon-button" type="button" aria-label="Add course" title="Add course" onclick={() => (createBoardOpen = true)}><Plus size={16} /></button></div>
      <nav class="study-course-list" aria-label="Courses">
        <a class:active={overview.isAllCoursesSelected} class="study-course-link" href="/app" aria-current={overview.isAllCoursesSelected ? 'page' : undefined}><Layers size={16} /><span>All courses</span></a>
        {#each overview.courseFilters as course (course.id)}
          <a class:active={course.isSelected} class="study-course-link" href={course.href} aria-current={course.isSelected ? 'page' : undefined}><span class={`study-course-accent ${course.colorClass}`} aria-hidden="true"></span><span>{course.name}</span><small class:muted={!course.hasGrade}>{course.gradeDisplay}</small></a>
        {/each}
      </nav>
      <div class="study-availability-summary">
        <button type="button" onclick={() => (availabilityOpen = true)}>
          <span><Clock3 size={14} />Availability</span>
          <strong>{durationLabel(weeklyCapacity)} / week</strong>
          <small>{recurringCommitments.length} fixed · {blockedDates.length} blocked</small>
        </button>
      </div>
    </aside>

    <section class="study-week" aria-labelledby="study-week-title">
      <header class="study-week-header">
        <div class="study-week-title">
          <h1 id="study-week-title">This week</h1>
          <p>{weekState}</p>
          <div class="study-week-actions">
            <button class="button primary large" type="button" disabled={!overview.hasPlanCandidates || pending} onclick={autoPlanWeek}><Strategy size={16} />{pending ? 'Working…' : 'Plan this week'}</button>
            <button class="button large" type="button" disabled={!overview.hasCourses} onclick={() => (createTaskOpen = true)}><Plus size={16} />Add assignment</button>
          </div>
          {#if requestError && !planOpen && !createTaskOpen && !availabilityOpen && !estimatesOpen && !completeOpen && !moveOpen}<p class="error-message" role="alert">{requestError}</p>{/if}
        </div>
        <section class="study-unplanned" aria-labelledby="study-unplanned-title">
          <h2 id="study-unplanned-title">Needs study time</h2>
          {#if unplannedPreview.length}
            <div class="study-unplanned-list">
              {#each unplannedPreview as assignment (assignment.id)}<button type="button" onclick={() => openPlan(assignment.id)}><strong>{assignment.title}</strong><small>{assignment.courseName} · {assignment.remainingDisplay} left · {assignment.dueDisplay}</small></button>{/each}
            </div>
            {#if overview.planCandidates.length > unplannedPreview.length}<span class="study-unplanned-rest">{overview.planCandidates.length - unplannedPreview.length} more waiting</span>{/if}
          {:else}<p class="study-unplanned-empty">Every estimated assignment is fully planned.</p>{/if}
        </section>
      </header>

      {#if overview.recovery.hasIssues}
        <section class="study-workflow-band recovery" aria-label="Week repair">
          <span class="study-workflow-mark" aria-hidden="true">↺</span>
          <div><strong>Your week changed</strong><p>{overview.recovery.summary} Missed work will return to open time.</p></div>
          <button class="button primary" type="button" disabled={pending} onclick={repairWeek}>{pending ? 'Repairing…' : 'Repair my week'}</button>
        </section>
      {:else if overview.onboarding.isVisible && currentOnboardingStep}
        <section class="study-workflow-band onboarding" aria-label="Set up your planner">
          <div class="study-onboarding-progress" aria-label={`${overview.onboarding.completedStepCount} of 5 setup steps complete`}>
            {#each overview.onboarding.steps as step}<span class:complete={step.isComplete} class:current={step.isCurrent}></span>{/each}
          </div>
          <div><strong>{currentOnboardingStep.title}</strong><p>{currentOnboardingStep.description}</p></div>
          {#if currentOnboardingStep.href}<a class="button primary" href={currentOnboardingStep.href}>Continue</a>{:else}<button class="button primary" type="button" disabled={pending} onclick={runOnboardingStep}>Continue</button>{/if}
        </section>
      {:else if overview.hasEstimationInbox}
        <section class="study-workflow-band estimates" aria-label="Assignments need estimates">
          <span class="study-workflow-mark" aria-hidden="true">{overview.estimationInbox.length}</span>
          <div><strong>Estimate inbox</strong><p>Add effort to every assignment in one pass.</p></div>
          <button class="button" type="button" onclick={() => (estimatesOpen = true)}>Estimate assignments</button>
        </section>
      {/if}

      <div class="study-days" aria-label={`Assignments due ${overview.weekLabel}`}>
        {#each overview.days as day, index}
          <section class:today={day.isToday} class:collapsed={expandedDays[day.dateLabel] === false} class:needs-repair={day.isOverloaded} class="study-day" data-load={loadClass(day)} style={`view-transition-name: study-day-${index}`}>
            <div class="study-day-date">
              <span class="study-day-weekday">{day.weekdayLabel}</span><strong>{day.dateLabel}</strong>{#if day.isToday}<small>Today</small>{/if}
              <span class="study-day-load" title={`${loadLabel(day)} · ${durationLabel(day.workloadMinutes)} planned of ${durationLabel(day.availableMinutes)} available`}>
                <span class="study-day-track" aria-hidden="true"><span class="study-day-bar" style={`width: ${loadPercent(day)}%`}></span></span>
                <span class="study-day-load-time">{durationLabel(day.workloadMinutes)} / {durationLabel(day.availableMinutes)}</span>
                <span class="sr-only">{loadLabel(day)}</span>
              </span>
            </div>
            <div class="study-day-content-shell">
              {#if expandedDays[day.dateLabel] === false}
                <div class="study-day-summary">
                  {#if day.hasAssignments}<span class="study-day-summary-count">{day.assignmentCount} {day.assignmentCount === 1 ? 'deadline' : 'deadlines'}</span><strong>{day.assignments[0].title}</strong><span class="study-day-summary-meta">{day.assignments[0].dueTime} · {day.assignments[0].effortLabel}{#if day.assignmentCount > 1} · +{day.assignmentCount - 1} more{/if}</span>
                  {:else if day.hasFocusBlocks}<span class="study-day-summary-count">{day.focusBlockCount} blocks</span><strong>{day.focusBlocks[0].title}</strong><span class="study-day-summary-meta">{day.focusBlocks[0].effortLabel}</span>
                  {:else}<span class="study-day-summary-count">{day.isBlocked ? 'Blocked' : 'Open day'}</span><strong>{day.isBlocked ? 'No study time available' : 'No deadlines or work planned'}</strong>{/if}
                </div>
              {:else}
                <div class="study-day-content">
                  {#if day.hasAssignments}
                    <div class="study-assignment-scroller" use:scrollFades><div class="study-assignment-track">
                      {#each day.assignments as assignment}<a class={`study-assignment ${assignment.courseColorClass}`} href={assignment.href} use:taskPreview={previewFromAssignment(assignment)}><span class="study-assignment-header"><span class="study-assignment-course">{assignment.courseName}</span><span class="study-assignment-due"><CalendarDays size={13} />{assignment.dueTime}</span></span><strong title={assignment.title}>{assignment.title}</strong><span class="study-assignment-footer"><span><FileText size={14} />{assignment.typeName}</span><span><Clock3 size={14} />{assignment.effortLabel}</span><OpenAssignment class="study-assignment-open" size={14} aria-hidden="true" /></span></a>{/each}
                    </div></div>
                  {:else}<span class="study-no-assignments">{day.isBlocked ? 'Blocked date' : 'No deadlines'}</span>{/if}
                  {#if day.hasFocusBlocks}
                    <div class="study-focus-blocks" aria-label={`Study blocks for ${day.weekdayLabel}`}>
                      <span class="study-focus-heading">Study</span>
                      {#each day.focusBlocks as assignment}
                        <span class:completed={assignment.sessionState === 'completed'} class:skipped={assignment.sessionState === 'skipped'} class="study-focus-item">
                          <a class="study-focus-chip" href={assignment.href} use:taskPreview={previewFromAssignment(assignment)}><span class={`study-focus-dot ${assignment.courseColorClass}`} aria-hidden="true"></span><strong>{assignment.title}</strong><small>{assignment.effortLabel}</small>{#if assignment.sessionState === 'completed'}<em>Done</em>{:else if assignment.sessionState === 'skipped'}<em>Skipped</em>{/if}</a>
                          {#if day.isToday && assignment.isPlannedSession}
                            <span class="study-focus-actions"><button type="button" disabled={pending} onclick={() => openComplete(assignment)}>Done</button><button type="button" disabled={pending} onclick={() => openMove(assignment)}>Move</button><button type="button" disabled={pending} onclick={() => skipSession(assignment.studySessionID)}>Skip</button></span>
                          {:else if assignment.hasStudySession && assignment.isPlannedSession}
                            <button class="study-focus-remove" type="button" disabled={pending} aria-label={`Remove ${assignment.title} study session`} title="Remove study session" onclick={() => deleteStudySession(assignment.studySessionID)}><Trash2 size={12} /></button>
                          {/if}
                        </span>
                      {/each}
                    </div>
                  {/if}
                </div>
              {/if}
            </div>
            <button class="study-day-toggle" type="button" aria-expanded={expandedDays[day.dateLabel] !== false} aria-label={`${expandedDays[day.dateLabel] !== false ? 'Collapse' : 'Expand'} ${day.weekdayLabel}. ${loadLabel(day)}.`} onclick={() => toggleDay(day.dateLabel)}><span class="study-day-toggle-label">{expandedDays[day.dateLabel] !== false ? 'Hide day' : 'Show day'}</span><span class="study-day-toggle-icons" aria-hidden="true"><Minus class="collapse-icon" size={13} /><Plus class="expand-icon" size={13} /></span></button>
          </section>
        {/each}
      </div>
      <footer class="study-week-footer">
        {#if overview.hasUnestimatedAssignments}<button type="button" onclick={() => (estimatesOpen = true)}><Clock3 size={15} />{overview.unestimatedAssignmentCount} assignments need time estimates</button>
        {:else if overview.hasUnscheduledAssignments}<a href="/app/tasks"><CalendarDays size={15} />{overview.unscheduledAssignmentCount} assignments still need a due date</a>
        {:else}<span><CalendarDays size={15} />Assignments without a time are due all day</span>{/if}
      </footer>
    </section>
  </div>
</div>

<CreateBoardDialog bind:open={createBoardOpen} />

{#if createTaskOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="new-assignment-title" tabindex="-1" use:dialogLayer={{ close: () => (createTaskOpen = false) }}><form class="dialog wide" onsubmit={createAssignment}><div class="dialog-header"><div><h2 id="new-assignment-title">Add assignment</h2><p>Put the deadline on your week, then add details when you need them.</p></div><button class="icon-button" type="button" onclick={() => (createTaskOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<div class="form-grid"><div class="field wide"><label for="assignment-title">Title</label><input class="input" id="assignment-title" name="title" maxlength="120" required data-dialog-focus /></div><div class="field"><label for="assignment-course">Course</label><SelectMenu id="assignment-course" name="boardID" value={overview.defaultCourseID} options={courseOptions} ariaLabel="Course" /></div><div class="field"><label for="assignment-due">Due date</label><DatePicker id="assignment-due" name="dueAt" label="Due date" /></div><div class="field"><label for="assignment-time">Due time</label><TimePicker id="assignment-time" name="dueTime" label="Due time" /></div><div class="field"><label for="assignment-estimate">Time estimate</label><input class="input" id="assignment-estimate" name="estimatedMinutes" type="number" min="5" max="1440" step="5" inputmode="numeric" placeholder="Minutes" /><span class="field-help">Use minutes, such as 45 or 120.</span></div><div class="field wide"><label for="assignment-description">Notes</label><textarea class="textarea" id="assignment-description" name="description" maxlength="5000"></textarea></div><div class="field wide"><label for="assignment-labels">Type</label><input class="input" id="assignment-labels" name="labels" maxlength="500" placeholder="Lab report, Reading, Discussion" /></div></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (createTaskOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Adding…' : 'Add assignment'}</button></div></form></div>
{/if}

{#if planOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="plan-week-title" tabindex="-1" use:dialogLayer={{ close: () => (planOpen = false) }}><form class="dialog" onsubmit={planAssignment}><div class="dialog-header"><div><h2 id="plan-week-title">Add study time</h2><p>Choose an assignment, date, and amount. Its deadline stays unchanged.</p></div><button class="icon-button" type="button" onclick={() => (planOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<div class="form-grid"><div class="field wide"><label for="plan-assignment">Assignment</label><SelectMenu id="plan-assignment" name="taskID" bind:value={planSelection} options={planOptions} ariaLabel="Assignment to plan" onchange={selectPlan} initialFocus /></div><div class="field"><label for="plan-date">Work on</label><DatePicker id="plan-date" name="focusDate" value={todayDateInput} label="Work on" required /></div><div class="field"><label for="plan-minutes">Planned minutes</label><input class="input" id="plan-minutes" name="plannedMinutes" type="number" min="5" max={planRemainingMinutes} step="5" bind:value={planMinutes} required /><span class="field-help">{durationLabel(planRemainingMinutes)} remains in the estimate.</span></div></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (planOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Planning…' : 'Add study session'}</button></div></form></div>
{/if}

{#if completeOpen && activeSession}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="complete-session-title" tabindex="-1" use:dialogLayer={{ close: () => (completeOpen = false) }}><form class="dialog compact" onsubmit={completeSession}><div class="dialog-header"><div><h2 id="complete-session-title">Finish study block</h2><p>{activeSession.title}</p></div><button class="icon-button" type="button" onclick={() => (completeOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<div class="field"><label for="actual-minutes">Minutes completed</label><input class="input" id="actual-minutes" type="number" min="1" max="1440" step="5" bind:value={actualMinutes} required data-dialog-focus /><span class="field-help">The plan was {activeSession.effortLabel}.</span></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (completeOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : 'Done'}</button></div></form></div>
{/if}

{#if moveOpen && activeSession}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="move-session-title" tabindex="-1" use:dialogLayer={{ close: () => (moveOpen = false) }}><form class="dialog compact" onsubmit={moveSession}><div class="dialog-header"><div><h2 id="move-session-title">Move study block</h2><p>{activeSession.title}</p></div><button class="icon-button" type="button" onclick={() => (moveOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<div class="field"><label for="move-date">New study date</label><input class="input" id="move-date" type="date" min={todayDateInput} bind:value={moveDate} required data-dialog-focus /></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (moveOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Moving…' : 'Move'}</button></div></form></div>
{/if}

{#if estimatesOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="estimate-inbox-title" tabindex="-1" use:dialogLayer={{ close: () => (estimatesOpen = false) }}><form class="dialog study-estimate-dialog" onsubmit={saveEstimates}><div class="dialog-header"><div><h2 id="estimate-inbox-title">Estimate inbox</h2><p>Set every assignment once, then reuse the same defaults next time.</p></div><button class="icon-button" type="button" onclick={() => (estimatesOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<section class="study-preset-editor" aria-labelledby="estimate-defaults-title"><h3 id="estimate-defaults-title">Reusable defaults</h3><div>{#each estimatePresets as preset}<label><span>{preset.name}</span><span><input type="number" min="5" max="1440" step="5" bind:value={preset.minutes} /><small>min</small></span></label>{/each}</div></section><div class="study-estimate-list">{#each overview.estimationInbox as item}<article><div><strong>{item.title}</strong><small>{item.courseName} · {item.typeName} · {item.dueDisplay}</small></div><select aria-label={`Default for ${item.title}`} value={item.suggestedPresetID} onchange={(event) => applyPreset(item.id, (event.currentTarget as HTMLSelectElement).value)}><option value="">Custom</option>{#each estimatePresets as preset}<option value={preset.id}>{preset.name}</option>{/each}</select><label><span class="sr-only">Minutes for {item.title}</span><input type="number" min="5" max="1440" step="5" bind:value={estimateValues[item.id]} required /><small>min</small></label></article>{/each}</div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (estimatesOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : `Save ${overview.estimationInbox.length} estimates`}</button></div></form></div>
{/if}

{#if availabilityOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="availability-title" tabindex="-1" use:dialogLayer={{ close: () => (availabilityOpen = false) }}><form class="dialog study-availability-dialog" onsubmit={saveAvailability}><div class="dialog-header"><div><h2 id="availability-title">Your real week</h2><p>Capacity is study time before classes, work, and calendar conflicts.</p></div><button class="icon-button" type="button" onclick={() => (availabilityOpen = false)} aria-label="Close"><X size={16} /></button></div><div class="dialog-body">{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}<section class="study-availability-section"><div class="study-section-heading"><h3>Weekday capacity</h3><span>Minutes</span></div><div class="study-capacity-grid">{#each weekdays as day}<label><span>{day.label}</span><input type="number" min="0" max="1440" step="15" bind:value={weekdayCapacityMinutes[day.key]} /></label>{/each}</div></section><section class="study-availability-section"><div class="study-section-heading"><h3>Blocked dates</h3><span>No study work</span></div><div class="study-inline-add"><input class="input" type="date" bind:value={blockedDateDraft} /><button class="button" type="button" onclick={addBlockedDate}>Block date</button></div><div class="study-setting-chips">{#each blockedDates as date}<span>{date}<button type="button" aria-label={`Remove blocked date ${date}`} onclick={() => (blockedDates = blockedDates.filter((item) => item !== date))}>×</button></span>{/each}</div></section><section class="study-availability-section"><div class="study-section-heading"><h3>Classes and work</h3><span>Repeats weekly</span></div><div class="study-setting-list">{#each recurringCommitments as item}<article><span><strong>{item.title}</strong><small>{item.kind} · {item.startTime}–{item.endTime}</small></span><button type="button" aria-label={`Remove ${item.title}`} onclick={() => (recurringCommitments = recurringCommitments.filter((value) => value.id !== item.id))}>Remove</button></article>{/each}</div><div class="study-commitment-builder"><input class="input" aria-label="Commitment title" placeholder="Calculus or work shift" bind:value={commitmentTitle} /><select class="input" aria-label="Commitment type" bind:value={commitmentKind}><option value="class">Class</option><option value="work">Work</option></select><input class="input" aria-label="Start time" type="time" bind:value={commitmentStart} /><input class="input" aria-label="End time" type="time" bind:value={commitmentEnd} /><fieldset><legend>Weekdays</legend>{#each weekdays as day}<label><input type="checkbox" checked={commitmentWeekdays.includes(day.index)} onchange={(event) => toggleCommitmentWeekday(day.index, (event.currentTarget as HTMLInputElement).checked)} /><span>{day.label}</span></label>{/each}</fieldset><button class="button" type="button" onclick={addCommitment}>Add fixed time</button></div></section><section class="study-availability-section"><div class="study-section-heading"><h3>Calendar conflicts</h3><span>One-time events</span></div><div class="study-setting-list">{#each calendarConflicts as item}<article><span><strong>{item.title}</strong><small>{item.date} · {item.startTime}–{item.endTime}</small></span><button type="button" aria-label={`Remove ${item.title}`} onclick={() => (calendarConflicts = calendarConflicts.filter((value) => value.id !== item.id))}>Remove</button></article>{/each}</div><div class="study-conflict-builder"><input class="input" aria-label="Conflict title" placeholder="Appointment" bind:value={conflictTitle} /><input class="input" aria-label="Conflict date" type="date" bind:value={conflictDate} /><input class="input" aria-label="Conflict start" type="time" bind:value={conflictStart} /><input class="input" aria-label="Conflict end" type="time" bind:value={conflictEnd} /><button class="button" type="button" onclick={addConflict}>Add conflict</button></div></section></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (availabilityOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : 'Save availability'}</button></div></form></div>
{/if}
