import { configure, makeAutoObservable, runInAction } from 'mobx';

const THEME_STORAGE_KEY = 'flowboard-theme';
const SIDEBAR_STORAGE_KEY = 'flowboard-sidebar';

export type Theme = 'light' | 'dark';

export type ToastNotification = {
  id: number;
  message: string;
};

export type TaskPreview = {
  assignee: string;
  board: string;
  body: string;
  due: string;
  priority: string;
  priorityClass: string;
  priorityColor?: string;
  status: string;
  statusClass: string;
  statusColor?: string;
  title: string;
};

export type UploadPhase = 'idle' | 'uploading' | 'saving' | 'error';

export type UploadState = {
  error: string | null;
  fileName: string | null;
  percent: number | null;
  phase: UploadPhase;
  progressVisible: boolean;
};

/** Inputs for a task move that the board sends to the JSON API. */
export type TaskMoveRequest = {
  csrfToken: string;
  status: string;
  targetIndex: number;
  taskID: string;
};

let nextNotificationID = 0;

// All state changes go through store actions. This makes async changes explicit
// when several Stimulus controllers use the same state.
configure({ enforceActions: 'always' });

function readStorage(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // The state still works for the current page when storage is unavailable.
  }
}

function initialTheme(): Theme {
  const stored = readStorage(THEME_STORAGE_KEY);
  if (stored === 'light' || stored === 'dark') {
    return stored;
  }
  return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function emptyUpload(): UploadState {
  return {
    error: null,
    fileName: null,
    percent: null,
    phase: 'idle',
    progressVisible: false,
  };
}

/**
 * Owns shared browser preferences, overlays, feedback, and request state.
 * The server remains the source of truth for boards, tasks, and form data.
 */
export class AppStore {
  theme: Theme = initialTheme();
  sidebarCollapsed = readStorage(SIDEBAR_STORAGE_KEY) === 'collapsed';
  sidebarOpen = false;
  activeOverlayID: string | null = null;
  notification: ToastNotification | null = null;
  taskPreview: TaskPreview | null = null;
  upload: UploadState = emptyUpload();
  pendingTaskMoveIDs = new Set<string>();

  constructor() {
    makeAutoObservable(this, {}, { autoBind: true });
  }

  /** Changes the theme and saves the preference for the next browser session. */
  toggleTheme(): void {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    writeStorage(THEME_STORAGE_KEY, this.theme);
  }

  /** Changes the desktop rail width and saves the preference. */
  toggleSidebarCollapsed(): void {
    this.sidebarCollapsed = !this.sidebarCollapsed;
    writeStorage(SIDEBAR_STORAGE_KEY, this.sidebarCollapsed ? 'collapsed' : 'expanded');
  }

  /** Opens the temporary sidebar drawer on small screens. */
  openSidebar(): void {
    this.sidebarOpen = true;
  }

  /** Closes the temporary sidebar drawer on small screens. */
  closeSidebar(): void {
    this.sidebarOpen = false;
  }

  /** Opens one menu or dialog and closes the previously active overlay. */
  openOverlay(id: string): void {
    this.activeOverlayID = id;
  }

  /** Closes the overlay only when the caller still owns it. */
  closeOverlay(id: string): void {
    if (this.activeOverlayID === id) {
      this.activeOverlayID = null;
    }
  }

  /** Replaces the active toast so repeated messages restart its display time. */
  showNotification(message: string): void {
    nextNotificationID += 1;
    this.notification = { id: nextNotificationID, message };
  }

  /** Clears a toast only if its display timer still owns the active message. */
  dismissNotification(id: number): void {
    if (this.notification?.id === id) {
      this.notification = null;
    }
  }

  /** Sets the task preview that the global preview surface must render. */
  showTaskPreview(preview: TaskPreview): void {
    this.taskPreview = preview;
  }

  /** Clears any task preview that is visible or waiting to render. */
  hideTaskPreview(): void {
    this.taskPreview = null;
  }

  /** Resets upload feedback when a file form connects. */
  resetUpload(): void {
    this.upload = emptyUpload();
  }

  /** Records the selected file and clears feedback from the prior selection. */
  selectUploadFile(fileName: string | null): void {
    this.upload = { ...emptyUpload(), fileName };
  }

  /** Shows a validation error without showing a network progress panel. */
  rejectUpload(message: string): void {
    this.upload = { ...this.upload, error: message };
  }

  /** Starts network progress for the selected file. */
  startUpload(): void {
    this.upload = {
      ...this.upload,
      error: null,
      percent: 0,
      phase: 'uploading',
      progressVisible: true,
    };
  }

  /** Updates measurable upload progress or sets an indeterminate value. */
  updateUploadProgress(percent: number | null): void {
    this.upload = { ...this.upload, percent };
  }

  /** Marks the server-side save that follows the browser upload. */
  saveUpload(): void {
    this.upload = { ...this.upload, percent: 100, phase: 'saving' };
  }

  /** Stops the busy state and shows a recoverable upload error. */
  failUpload(message: string): void {
    this.upload = {
      ...this.upload,
      error: message,
      phase: 'error',
      progressVisible: true,
    };
  }

  /**
   * Saves one drag operation and exposes its pending state to every board view.
   * A rejected request throws so the controller can restore the server view.
   */
  async moveTask(request: TaskMoveRequest): Promise<void> {
    if (this.pendingTaskMoveIDs.has(request.taskID)) {
      throw new Error('This task move is already pending.');
    }

    this.pendingTaskMoveIDs.add(request.taskID);
    try {
      const response = await fetch(`/api/v1/tasks/${request.taskID}/move`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': request.csrfToken,
        },
        body: JSON.stringify({ status: request.status, targetIndex: request.targetIndex }),
      });
      if (!response.ok) {
        throw new Error('The task move was rejected.');
      }
    } finally {
      runInAction(() => this.pendingTaskMoveIDs.delete(request.taskID));
    }
  }
}

export const appStore = new AppStore();
