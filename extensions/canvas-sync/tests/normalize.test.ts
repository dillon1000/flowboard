import { describe, expect, it } from 'vitest';
import { canvasHTMLToText } from '../src/html';
import {
  canvasSubmissionIsComplete,
  normalizeCanvasAssignment,
  normalizeCanvasCourse,
  normalizeCanvasSubmission
} from '../src/normalize';

const origin = 'https://school.instructure.com';

describe('Canvas normalization', () => {
  it('normalizes course totals and term data', () => {
    expect(normalizeCanvasCourse({
      id: 42,
      name: 'Biology',
      course_code: 'BIO-101',
      term: { name: 'Fall 2026' },
      html_url: `${origin}/courses/42`,
      enrollments: [{ computed_current_score: 108.5, computed_current_grade: 'A+' }]
    }, origin)).toMatchObject({
      id: '42',
      courseCode: 'BIO-101',
      termName: 'Fall 2026',
      currentScore: 108.5,
      currentGrade: 'A+'
    });
  });

  it('normalizes effective assignment and submission fields', () => {
    expect(normalizeCanvasAssignment({
      id: '9',
      name: 'Lab',
      description: '<p>Read <strong>carefully</strong>.</p><p>Submit results.</p>',
      html_url: `${origin}/courses/42/assignments/9`,
      due_at: '2026-09-01T20:00:00Z',
      points_possible: 0,
      submission: {
        workflow_state: 'pending_review',
        grade: null,
        score: 2,
        submitted_at: '2026-08-30T12:00:00Z',
        late: true,
        missing: false,
        excused: false,
        redo_request: true
      }
    }, origin)).toMatchObject({
      id: '9',
      descriptionText: 'Read carefully.\nSubmit results.',
      pointsPossible: 0,
      submission: { workflowState: 'pending_review', score: 2, late: true, redoRequested: true }
    });
  });

  it('maps complete and reopened submission states', () => {
    const submitted = normalizeCanvasSubmission({ workflow_state: 'submitted' });
    const excused = normalizeCanvasSubmission({ workflow_state: 'unsubmitted', excused: true });
    const excusedState = normalizeCanvasSubmission({ workflow_state: 'excused' });
    const reassigned = normalizeCanvasSubmission({ workflow_state: 'unsubmitted', redo_request: true });
    expect(canvasSubmissionIsComplete(submitted)).toBe(true);
    expect(canvasSubmissionIsComplete(excused)).toBe(true);
    expect(canvasSubmissionIsComplete(excusedState)).toBe(true);
    expect(canvasSubmissionIsComplete(reassigned)).toBe(false);
  });
});

describe('Canvas HTML text', () => {
  it('removes scripts, keeps paragraph breaks, and limits output', () => {
    const text = canvasHTMLToText(`<p>First&nbsp;line</p><script>secret()</script><div>${'x'.repeat(5_100)}</div>`);
    expect(text).not.toContain('secret');
    expect(text?.startsWith('First line\n')).toBe(true);
    expect(text?.length).toBe(5_000);
  });
});
