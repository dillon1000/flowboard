<script lang="ts">
  import { api, messageFor } from '$lib/api';
  import DatePicker from '$lib/components/DatePicker.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';
  import TimePicker from '$lib/components/TimePicker.svelte';
  import type { StudyCalendarConflict, StudyRecurringCommitment, StudySettingsContext } from '$lib/types';
  import { durationLabel } from '$lib/ui/deadline';
  import { showToast } from '$lib/ui/toast';
  import { ArrowLeftIcon as ArrowLeft } from 'phosphor-svelte';

  const weekdays = [
    { key: 'monday', label: 'Mon', index: 1 },
    { key: 'tuesday', label: 'Tue', index: 2 },
    { key: 'wednesday', label: 'Wed', index: 3 },
    { key: 'thursday', label: 'Thu', index: 4 },
    { key: 'friday', label: 'Fri', index: 5 },
    { key: 'saturday', label: 'Sat', index: 6 },
    { key: 'sunday', label: 'Sun', index: 7 }
  ] as const;
  const commitmentKindOptions: SelectMenuOption[] = [
    { value: 'class', label: 'Class' },
    { value: 'work', label: 'Work' }
  ];
  const dateFormatter = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC'
  });

  let { settings } = $props<{ settings: StudySettingsContext }>();
  const initialSettings = $state.snapshot((() => settings)());
  let weekdayCapacityMinutes = $state<Record<string, number>>({ ...initialSettings.weekdayCapacityMinutes });
  let blockedDates = $state<string[]>([...initialSettings.blockedDates]);
  let recurringCommitments = $state<StudyRecurringCommitment[]>(initialSettings.recurringCommitments.map((item: StudyRecurringCommitment) => ({ ...item, weekdays: [...item.weekdays] })));
  let calendarConflicts = $state<StudyCalendarConflict[]>(initialSettings.calendarConflicts.map((item: StudyCalendarConflict) => ({ ...item })));
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
  let pending = $state(false);
  let requestError = $state('');
  const weeklyCapacity = $derived(Object.values(weekdayCapacityMinutes).reduce((total, minutes) => total + Number(minutes), 0));

  function dateLabel(value: string): string {
    const date = new Date(`${value}T00:00:00Z`);
    return Number.isNaN(date.getTime()) ? value : dateFormatter.format(date);
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

  async function saveAvailability(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    pending = true;
    requestError = '';
    try {
      await api('/api/v1/study-settings', {
        method: 'PUT',
        body: JSON.stringify({
          weekdayCapacityMinutes: Object.fromEntries(Object.entries(weekdayCapacityMinutes).map(([key, value]) => [key, Number(value)])),
          blockedDates,
          recurringCommitments,
          calendarConflicts,
          estimatePresets: settings.estimatePresets,
          timeZoneConfirmed: settings.timeZoneConfirmed,
          availabilityConfigured: true
        })
      });
      showToast('Availability saved');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

<div class="page narrow">
  <header class="page-header">
    <div class="page-title"><h1>Availability</h1><p>Set the time that the weekly planner can use around your fixed schedule.</p></div>
    <a class="button" href="/app"><ArrowLeft size={15} />Back to week</a>
  </header>
  <div class="settings-grid">
    <SettingsNavigation active="availability" />
    <div class="settings-content">
      <form class="panel availability-settings-form" onsubmit={saveAvailability}>
        <div class="availability-settings-summary"><span>Weekly study capacity</span><strong>{durationLabel(weeklyCapacity)}</strong></div>
        {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

        <section class="study-availability-section" aria-labelledby="weekday-capacity-title">
          <div class="study-section-heading"><h2 id="weekday-capacity-title">Weekday capacity</h2><span>Minutes</span></div>
          <p class="field-help">Enter the study time available before fixed classes, work, and conflicts are subtracted.</p>
          <div class="study-capacity-grid">{#each weekdays as day}<label><span>{day.label}</span><input type="number" min="0" max="1440" step="15" bind:value={weekdayCapacityMinutes[day.key]} /></label>{/each}</div>
        </section>

        <section class="study-availability-section" aria-labelledby="blocked-dates-title">
          <div class="study-section-heading"><h2 id="blocked-dates-title">Blocked dates</h2><span>No study work</span></div>
          <div class="study-inline-add"><DatePicker id="blocked-date" name="blockedDate" label="Blocked date" bind:value={blockedDateDraft} /><button class="button" type="button" onclick={addBlockedDate}>Block date</button></div>
          <div class="study-setting-chips">{#each blockedDates as date}<span>{dateLabel(date)}<button type="button" aria-label={`Remove blocked date ${dateLabel(date)}`} onclick={() => (blockedDates = blockedDates.filter((item) => item !== date))}>×</button></span>{/each}</div>
        </section>

        <section class="study-availability-section" aria-labelledby="fixed-time-title">
          <div class="study-section-heading"><h2 id="fixed-time-title">Classes and work</h2><span>Repeats weekly</span></div>
          <div class="study-setting-list">{#each recurringCommitments as item}<article><span><strong>{item.title}</strong><small>{item.kind} · {item.startTime}–{item.endTime}</small></span><button type="button" aria-label={`Remove ${item.title}`} onclick={() => (recurringCommitments = recurringCommitments.filter((value) => value.id !== item.id))}>Remove</button></article>{/each}</div>
          <div class="study-commitment-builder">
            <input class="input" aria-label="Commitment title" placeholder="Calculus or work shift" bind:value={commitmentTitle} />
            <SelectMenu id="commitment-kind" name="commitmentKind" bind:value={commitmentKind} options={commitmentKindOptions} ariaLabel="Commitment type" />
            <TimePicker id="commitment-start" name="commitmentStart" label="Start time" bind:value={commitmentStart} />
            <TimePicker id="commitment-end" name="commitmentEnd" label="End time" bind:value={commitmentEnd} />
            <fieldset><legend>Weekdays</legend>{#each weekdays as day}<label><input type="checkbox" checked={commitmentWeekdays.includes(day.index)} onchange={(event) => toggleCommitmentWeekday(day.index, (event.currentTarget as HTMLInputElement).checked)} /><span>{day.label}</span></label>{/each}</fieldset>
            <button class="button" type="button" onclick={addCommitment}>Add fixed time</button>
          </div>
        </section>

        <section class="study-availability-section" aria-labelledby="calendar-conflicts-title">
          <div class="study-section-heading"><h2 id="calendar-conflicts-title">Calendar conflicts</h2><span>One-time events</span></div>
          <div class="study-setting-list">{#each calendarConflicts as item}<article><span><strong>{item.title}</strong><small>{dateLabel(item.date)} · {item.startTime}–{item.endTime}</small></span><button type="button" aria-label={`Remove ${item.title}`} onclick={() => (calendarConflicts = calendarConflicts.filter((value) => value.id !== item.id))}>Remove</button></article>{/each}</div>
          <div class="study-conflict-builder">
            <input class="input" aria-label="Conflict title" placeholder="Appointment" bind:value={conflictTitle} />
            <DatePicker id="conflict-date" name="conflictDate" label="Conflict date" bind:value={conflictDate} />
            <TimePicker id="conflict-start" name="conflictStart" label="Conflict start" bind:value={conflictStart} />
            <TimePicker id="conflict-end" name="conflictEnd" label="Conflict end" bind:value={conflictEnd} />
            <button class="button" type="button" onclick={addConflict}>Add conflict</button>
          </div>
        </section>

        <div class="form-actions availability-settings-actions"><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : 'Save availability'}</button></div>
      </form>
    </div>
  </div>
</div>
