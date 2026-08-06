export interface CanvasSyncSnapshotV1 {
  version: 1;
  snapshotID: string;
  canvasOrigin: string;
  capturedAt: string;
  courses: CanvasCourseSnapshot[];
}

export interface CanvasCourseSnapshot {
  id: string;
  name: string;
  courseCode: string | null;
  termName: string | null;
  htmlURL: string;
  currentScore: number | null;
  currentGrade: string | null;
  assignments: CanvasAssignmentSnapshot[];
}

export interface CanvasAssignmentSnapshot {
  id: string;
  name: string;
  descriptionText: string | null;
  htmlURL: string;
  dueAt: string | null;
  pointsPossible: number | null;
  submission: CanvasSubmissionSnapshot | null;
}

export interface CanvasSubmissionSnapshot {
  workflowState: string | null;
  grade: string | null;
  score: number | null;
  submittedAt: string | null;
  late: boolean;
  missing: boolean;
  excused: boolean;
  redoRequested: boolean;
}

export interface CanvasSyncConfiguration {
  canvasOrigin: string;
  focalpointOrigin: string;
  syncKey: string;
}

export interface SyncResult {
  ok: boolean;
  code: SyncErrorCode | 'OK';
  message: string;
  attemptedAt: string;
  snapshotID?: string;
  duplicate?: boolean;
}

export type SyncErrorCode =
  | 'NOT_CONFIGURED'
  | 'CURRENT_TAB_MISMATCH'
  | 'SESSION_EXPIRED'
  | 'CANVAS_DENIED'
  | 'CANVAS_REQUEST_FAILED'
  | 'PAGINATION_FAILED'
  | 'RESPONSE_INVALID'
  | 'SYNC_KEY_INVALID'
  | 'FOCALPOINT_UNAVAILABLE'
  | 'FOCALPOINT_REJECTED'
  | 'SYNC_ACTIVE'
  | 'PERMISSION_DENIED';

export type ExtensionMessage =
  | { type: 'canvasPageReady' }
  | { type: 'collectCanvasSnapshot'; canvasOrigin: string }
  | { type: 'syncNow' }
  | { type: 'configurationChanged' }
  | { type: 'getPopupState' };

export interface PopupState {
  configuration: CanvasSyncConfiguration | null;
  lastResult: SyncResult | null;
}
