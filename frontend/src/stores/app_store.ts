import { configure, makeAutoObservable, runInAction } from 'mobx';

const THEME_STORAGE_KEY = 'flowboard-theme';
const SIDEBAR_STORAGE_KEY = 'flowboard-sidebar';
const PENDING_COMPLETION_KEY = 'flowboard-pending-completion';

export type Theme = 'light' | 'dark';

export type ToastNotification = {
  id: number;
  message: string;
};

export type ConfettiOrigin = {
  x: number;
  y: number;
};

export type CelebrationRequest = {
  id: number;
  origin?: ConfettiOrigin;
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

export type OverlayType = 'dialog' | 'menu';

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
let nextCelebrationID = 0;

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

function parseTheme(value: string | null): Theme | null {
  return value === 'light' || value === 'dark' ? value : null;
}

function readSessionStorage(key: string): string | null {
  try {
    return sessionStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeSessionStorage(key: string, value: string): void {
  try {
    sessionStorage.setItem(key, value);
  } catch {
    // The observable flag still covers Turbo navigation in this tab.
  }
}

function removeSessionStorage(key: string): void {
  try {
    sessionStorage.removeItem(key);
  } catch {
    // The observable flag is cleared even when storage is unavailable.
  }
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
  themePreference: Theme | null = parseTheme(readStorage(THEME_STORAGE_KEY));
  systemTheme: Theme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  sidebarCollapsed = readStorage(SIDEBAR_STORAGE_KEY) === 'collapsed';
  sidebarOpen = false;
  activeOverlayIDs: Record<OverlayType, string | null> = {
    dialog: null,
    menu: null,
  };
  notifications: ToastNotification[] = [];
  celebration: CelebrationRequest | null = null;
  completionPending = readSessionStorage(PENDING_COMPLETION_KEY) === 'true';
  taskPreview: TaskPreview | null = null;
  upload: UploadState = emptyUpload();
  pendingTaskMoveIDs = new Set<string>();

  constructor() {
    makeAutoObservable(this, {}, { autoBind: true });
  }

  /** Resolves an explicit browser choice over the current operating-system theme. */
  get theme(): Theme {
    return this.themePreference ?? this.systemTheme;
  }

  /** Returns the toast at the front of the observable display queue. */
  get notification(): ToastNotification | null {
    return this.notifications[0] ?? null;
  }

  /** Changes the theme and saves the preference for the next browser session. */
  toggleTheme(): void {
    this.themePreference = this.theme === 'dark' ? 'light' : 'dark';
    writeStorage(THEME_STORAGE_KEY, this.themePreference);
  }

  /** Updates the computed theme when the operating-system preference changes. */
  setSystemTheme(dark: boolean): void {
    this.systemTheme = dark ? 'dark' : 'light';
  }

  /** Applies preference changes made by another tab in the same browser. */
  syncStoredPreference(key: string | null, value: string | null): void {
    if (key === null || key === THEME_STORAGE_KEY) {
      this.themePreference = key === null
        ? parseTheme(readStorage(THEME_STORAGE_KEY))
        : parseTheme(value);
    }
    if (key === null || key === SIDEBAR_STORAGE_KEY) {
      const sidebarValue = key === null ? readStorage(SIDEBAR_STORAGE_KEY) : value;
      this.sidebarCollapsed = sidebarValue === 'collapsed';
    }
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

  /** Opens one overlay and closes the active overlay of the same type. */
  openOverlay(type: OverlayType, id: string): void {
    this.activeOverlayIDs[type] = id;
  }

  /** Closes an overlay only when the caller still owns its type slot. */
  closeOverlay(type: OverlayType, id: string): void {
    if (this.activeOverlayIDs[type] === id) {
      this.activeOverlayIDs[type] = null;
    }
  }

  /** Adds a toast to the display queue so rapid messages remain visible. */
  showNotification(message: string): void {
    nextNotificationID += 1;
    this.notifications.push({ id: nextNotificationID, message });
  }

  /** Removes a toast after its display timer completes. */
  dismissNotification(id: number): void {
    this.notifications = this.notifications.filter((notification) => notification.id !== id);
  }

  /** Requests one completion effect with an optional pointer-relative origin. */
  requestCelebration(origin?: ConfettiOrigin): void {
    nextCelebrationID += 1;
    this.celebration = { id: nextCelebrationID, origin };
  }

  /** Clears a completion effect only after its observer has handled it. */
  dismissCelebration(id: number): void {
    if (this.celebration?.id === id) {
      this.celebration = null;
    }
  }

  /** Saves a completion effect across a Turbo redirect or a full page load. */
  markCompletionPending(): void {
    this.completionPending = true;
    writeSessionStorage(PENDING_COMPLETION_KEY, 'true');
  }

  /** Returns and clears the completion effect queued by a successful form. */
  consumeCompletionPending(): boolean {
    if (!this.completionPending) {
      return false;
    }
    this.completionPending = false;
    removeSessionStorage(PENDING_COMPLETION_KEY);
    return true;
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
