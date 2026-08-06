import { SyncError } from './errors';
import { canvasHTMLToText } from './html';
import type { CanvasAssignmentSnapshot, CanvasCourseSnapshot, CanvasSubmissionSnapshot } from './types';

type RecordValue = Record<string, unknown>;

function record(value: unknown, name: string): RecordValue {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  }
  return value as RecordValue;
}

function requiredID(value: unknown, name: string): string {
  if ((typeof value !== 'string' && typeof value !== 'number') || String(value).trim() === '') {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name} ID.`);
  }
  return String(value);
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== 'string' || !value.trim()) {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  }
  return value.trim();
}

function optionalString(value: unknown, name: string): string | null {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string') throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  return value;
}

function optionalNumber(value: unknown, name: string): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  }
  return value;
}

function optionalDate(value: unknown, name: string): string | null {
  const text = optionalString(value, name);
  if (text === null) return null;
  if (Number.isNaN(Date.parse(text))) throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  return text;
}

function optionalBoolean(value: unknown, name: string): boolean {
  if (value === null || value === undefined) return false;
  if (typeof value !== 'boolean') throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  return value;
}

function sameOriginURL(value: unknown, canvasOrigin: string, name: string): string {
  const text = requiredString(value, name);
  let url: URL;
  try {
    url = new URL(text, canvasOrigin);
  } catch {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  }
  if (url.protocol !== 'https:' || url.origin !== canvasOrigin) {
    throw new SyncError('RESPONSE_INVALID', `Canvas returned an invalid ${name}.`);
  }
  return url.href;
}

export function normalizeCanvasCourse(value: unknown, canvasOrigin: string): CanvasCourseSnapshot {
  const course = record(value, 'course');
  const enrollments = course.enrollments;
  if (enrollments !== undefined && !Array.isArray(enrollments)) {
    throw new SyncError('RESPONSE_INVALID', 'Canvas returned invalid course enrollments.');
  }
  const enrollment = Array.isArray(enrollments) && enrollments.length > 0
    ? record(enrollments[0], 'course enrollment')
    : {};
  const term = course.term === null || course.term === undefined ? null : record(course.term, 'course term');
  return {
    id: requiredID(course.id, 'course'),
    name: requiredString(course.name, 'course name'),
    courseCode: optionalString(course.course_code, 'course code'),
    termName: term ? optionalString(term.name, 'term name') : null,
    htmlURL: sameOriginURL(course.html_url, canvasOrigin, 'course URL'),
    currentScore: optionalNumber(enrollment.computed_current_score ?? enrollment.current_score, 'course score'),
    currentGrade: optionalString(enrollment.computed_current_grade ?? enrollment.current_grade, 'course grade'),
    assignments: []
  };
}

export function normalizeCanvasSubmission(value: unknown): CanvasSubmissionSnapshot | null {
  if (value === null || value === undefined) return null;
  const submission = record(value, 'submission');
  return {
    workflowState: optionalString(submission.workflow_state, 'submission state'),
    grade: optionalString(submission.grade, 'grade label'),
    score: optionalNumber(submission.score, 'assignment score'),
    submittedAt: optionalDate(submission.submitted_at, 'submission date'),
    late: optionalBoolean(submission.late, 'late state'),
    missing: optionalBoolean(submission.missing, 'missing state'),
    excused: optionalBoolean(submission.excused, 'excused state'),
    redoRequested: optionalBoolean(submission.redo_request ?? submission.redo_requested, 'redo state')
  };
}

export function canvasSubmissionIsComplete(submission: CanvasSubmissionSnapshot | null): boolean {
  if (!submission) return false;
  return submission.excused || ['submitted', 'graded', 'pending_review'].includes(submission.workflowState ?? '');
}

export function normalizeCanvasAssignment(value: unknown, canvasOrigin: string): CanvasAssignmentSnapshot {
  const assignment = record(value, 'assignment');
  const descriptionHTML = optionalString(assignment.description, 'assignment description');
  return {
    id: requiredID(assignment.id, 'assignment'),
    name: requiredString(assignment.name, 'assignment name'),
    descriptionText: canvasHTMLToText(descriptionHTML),
    htmlURL: sameOriginURL(assignment.html_url, canvasOrigin, 'assignment URL'),
    dueAt: optionalDate(assignment.due_at, 'assignment due date'),
    pointsPossible: optionalNumber(assignment.points_possible, 'points possible'),
    submission: normalizeCanvasSubmission(assignment.submission)
  };
}
