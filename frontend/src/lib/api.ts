import type {
  Board,
  BoardSummary,
  Page,
  Task,
  TaskDraft,
  TaskStatus,
  User
} from './types';

// A relative default keeps the Leaf shell and API on one origin. VITE_API_URL
// remains available for a separate frontend host during development.
const API_URL = import.meta.env.VITE_API_URL ?? '/api/v1';

interface VaporError {
  reason?: string;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, {
    ...init,
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...init?.headers
    }
  });

  if (response.status === 401) {
    window.location.assign('/login');
    throw new Error('Your session has ended. Log in again.');
  }

  if (!response.ok) {
    const payload = (await response.json().catch(() => ({}))) as VaporError;
    throw new Error(payload.reason ?? `The server returned ${response.status}.`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export const api = {
  getMe: () => request<User>('/auth/me'),
  updateProfile: (name: string) =>
    request<User>('/auth/me', {
      method: 'PATCH',
      body: JSON.stringify({ name })
    }),
  logout: () => request<void>('/auth/logout', { method: 'POST' }),

  getBoards: () => request<BoardSummary[]>('/boards'),
  getDefaultBoard: () => request<Board>('/boards/default'),
  getBoard: (boardID: string) => request<Board>(`/boards/${boardID}`),
  createBoard: (name: string) =>
    request<Board>('/boards', {
      method: 'POST',
      body: JSON.stringify({ name, slug: null })
    }),
  updateBoard: (boardID: string, name: string) =>
    request<Board>(`/boards/${boardID}`, {
      method: 'PATCH',
      body: JSON.stringify({ name })
    }),
  deleteBoard: (boardID: string) =>
    request<void>(`/boards/${boardID}`, {
      method: 'DELETE'
    }),

  getTasks: (boardID?: string) => {
    const query = new URLSearchParams({ page: '1', per: '100' });
    if (boardID) {
      query.set('boardID', boardID);
    }
    return request<Page<Task>>(`/tasks?${query.toString()}`);
  },
  createTask: (boardID: string, draft: TaskDraft) =>
    request<Task>('/tasks', {
      method: 'POST',
      body: JSON.stringify({ boardID, ...draft })
    }),
  updateTask: (taskID: string, draft: TaskDraft) =>
    request<Task>(`/tasks/${taskID}`, {
      method: 'PATCH',
      body: JSON.stringify(draft)
    }),
  moveTask: (taskID: string, status: TaskStatus, targetIndex: number) =>
    request<Task>(`/tasks/${taskID}/move`, {
      method: 'POST',
      body: JSON.stringify({ status, targetIndex })
    }),
  deleteTask: (taskID: string) =>
    request<void>(`/tasks/${taskID}`, {
      method: 'DELETE'
    })
};
