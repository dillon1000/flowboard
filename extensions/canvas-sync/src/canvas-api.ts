import { fetchAllCanvasPages } from './pagination';
import { normalizeCanvasAssignment, normalizeCanvasCourse } from './normalize';
import type { CanvasSyncSnapshotV1 } from './types';

function coursesURL(canvasOrigin: string): string {
  const url = new URL('/api/v1/courses', canvasOrigin);
  url.searchParams.set('enrollment_type', 'student');
  url.searchParams.set('enrollment_state', 'active');
  url.searchParams.append('include[]', 'term');
  url.searchParams.append('include[]', 'total_scores');
  url.searchParams.set('per_page', '100');
  return url.href;
}

function assignmentsURL(canvasOrigin: string, courseID: string): string {
  const url = new URL(`/api/v1/courses/${encodeURIComponent(courseID)}/assignments`, canvasOrigin);
  url.searchParams.append('include[]', 'submission');
  url.searchParams.set('override_assignment_dates', 'true');
  url.searchParams.set('order_by', 'due_at');
  url.searchParams.set('per_page', '100');
  return url.href;
}

/** Reads a complete Canvas snapshot. No caller should send data after this rejects. */
export async function collectCanvasSnapshot(
  canvasOrigin: string,
  fetchPage: typeof fetch = fetch,
  snapshotID: () => string = () => crypto.randomUUID(),
  now: () => Date = () => new Date()
): Promise<CanvasSyncSnapshotV1> {
  const rawCourses = await fetchAllCanvasPages<unknown>(coursesURL(canvasOrigin), fetchPage);
  const courses = [];
  for (const rawCourse of rawCourses) {
    const course = normalizeCanvasCourse(rawCourse, canvasOrigin);
    const rawAssignments = await fetchAllCanvasPages<unknown>(
      assignmentsURL(canvasOrigin, course.id),
      fetchPage
    );
    course.assignments = rawAssignments.map((assignment) => normalizeCanvasAssignment(assignment, canvasOrigin));
    courses.push(course);
  }
  return {
    version: 1,
    snapshotID: snapshotID(),
    canvasOrigin,
    capturedAt: now().toISOString(),
    courses
  };
}
