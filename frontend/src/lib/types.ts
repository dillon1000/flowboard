export type TaskStatus = 'backlog' | 'in_progress' | 'review' | 'done';
export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent';

export interface User {
  id: string;
  name: string;
  email: string;
  createdAt: string | null;
}

export interface Task {
  id: string;
  boardID: string;
  boardName: string | null;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  position: number;
  labels: string[];
  dueAt: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface Board {
  id: string;
  name: string;
  slug: string;
  tasks: Task[];
  createdAt: string | null;
  updatedAt: string | null;
}

export interface BoardSummary {
  id: string;
  name: string;
  slug: string;
  taskCount: number;
  completedCount: number;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface TaskDraft {
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  labels: string[];
  dueAt: string | null;
}

export interface Page<T> {
  items: T[];
  metadata: {
    page: number;
    per: number;
    total: number;
    pageCount: number;
  };
}
