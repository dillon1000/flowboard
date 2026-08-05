export interface AvatarContext {
  initials: string;
  profilePictureURL: string;
  hasProfilePicture: boolean;
}

export interface BoardNavigationContext {
  id: string;
  name: string;
  description: string;
  href: string;
  courseColorClass: string;
  taskCount: number;
  completedCount: number;
  isArchived: boolean;
}

export interface CommonPageContext {
  userName: string;
  userEmail: string;
  userAvatar: AvatarContext;
  boards: BoardNavigationContext[];
}

export interface TaskOptionContext {
  value: string;
  name: string;
  colorClass: string;
  colorStyle: string;
  customColor: string;
  isSelected: boolean;
  isCompleted: boolean;
}

export interface TaskCardContext {
  id: string;
  boardID: string;
  boardName: string;
  href: string;
  title: string;
  description: string;
  hasDescription: boolean;
  statusValue: string;
  statusName: string;
  statusColorClass: string;
  statusColorStyle: string;
  statusCustomColor: string;
  priorityValue: string;
  priorityName: string;
  priorityColorClass: string;
  priorityColorStyle: string;
  priorityCustomColor: string;
  labels: string[];
  labelsJoined: string;
  hasLabels: boolean;
  startInput: string;
  startDisplay: string;
  dueInput: string;
  dueDisplay: string;
  hasDueDate: boolean;
  dueTimeInput: string;
  dueTimeDisplay: string;
  hasDueTime: boolean;
  estimatedMinutes: number;
  estimatedDisplay: string;
  hasEstimate: boolean;
  gradeEarned: number;
  gradePossible: number;
  gradeDisplay: string;
  hasGrade: boolean;
  assigneeID: string;
  assigneeName: string;
  hasAssignee: boolean;
  commentCount: number;
  checklistCount: number;
  completedChecklistCount: number;
  attachmentCount: number;
  updatedDisplay: string;
  isArchived: boolean;
  canEdit: boolean;
  statusOptions: TaskOptionContext[];
  severityOptions: TaskOptionContext[];
  completionStatuses: string;
}

export interface StudyCourseContext {
  id: string;
  name: string;
  href: string;
  colorClass: string;
  isSelected: boolean;
  gradeDisplay: string;
  hasGrade: boolean;
}

export interface StudyAssignmentContext {
  href: string;
  title: string;
  courseName: string;
  courseColorClass: string;
  dueTime: string;
  typeName: string;
  typeIcon: string;
  estimatedMinutes: number;
  effortLabel: string;
  hasEstimate: boolean;
  statusName: string;
  statusValue: string;
  statusColorClass: string;
  statusCustomColor: string;
  priorityName: string;
  priorityValue: string;
  priorityColorClass: string;
  priorityCustomColor: string;
  assigneeName: string;
  dueDisplay: string;
  description: string;
}

export interface StudyPlanCandidateContext {
  id: string;
  title: string;
  courseName: string;
  dueDisplay: string;
  effortLabel: string;
}

export interface StudyDayContext {
  weekdayLabel: string;
  dateLabel: string;
  isToday: boolean;
  assignments: StudyAssignmentContext[];
  assignmentCount: number;
  hasAssignments: boolean;
  focusBlocks: StudyAssignmentContext[];
  focusBlockCount: number;
  hasFocusBlocks: boolean;
  workloadMinutes: number;
  unestimatedAssignmentCount: number;
  workloadLabel: string;
  workloadClass: string;
}

export interface StudyWorkloadDayContext {
  dayLabel: string;
  barClass: string;
  accessibilityLabel: string;
}

export interface OverviewPageContext {
  weekLabel: string;
  courseFilters: StudyCourseContext[];
  isAllCoursesSelected: boolean;
  defaultCourseID: string;
  defaultCourseName: string;
  hasCourses: boolean;
  returnHref: string;
  days: StudyDayContext[];
  workloadDays: StudyWorkloadDayContext[];
  balanceName: string;
  balanceDescription: string;
  unscheduledAssignmentCount: number;
  hasUnscheduledAssignments: boolean;
  unestimatedAssignmentCount: number;
  hasUnestimatedAssignments: boolean;
  planCandidates: StudyPlanCandidateContext[];
  hasPlanCandidates: boolean;
  unplannedFocusCount: number;
  hasUnplannedFocus: boolean;
  studyStreakDays: number;
}

export interface SemesterAssignmentContext {
  href: string;
  title: string;
  courseName: string;
  courseColorClass: string;
  dueInput: string;
  dueLabel: string;
  estimatedMinutes: number;
  effortLabel: string;
  hasEstimate: boolean;
}

export interface SemesterWeekContext {
  label: string;
  assignments: SemesterAssignmentContext[];
  assignmentCount: number;
  workloadLabel: string;
  workloadClass: string;
  isHighLoad: boolean;
}

export interface SemesterPageContext {
  rangeLabel: string;
  weeks: SemesterWeekContext[];
  scheduledAssignmentCount: number;
  highLoadWeekCount: number;
  undatedAssignmentCount: number;
  hasUndatedAssignments: boolean;
}

export interface TaskColumnContext {
  value: string;
  name: string;
  dotClass: string;
  dotStyle: string;
  isCompleted: boolean;
  tasks: TaskCardContext[];
  count: number;
}

export interface CalendarDayContext {
  day: string;
  isMuted: boolean;
  isToday: boolean;
  tasks: TaskCardContext[];
}

export interface BoardViewTabContext {
  id: string;
  name: string;
  type: string;
  href: string;
  isActive: boolean;
  isBoard: boolean;
  isTable: boolean;
  isCalendar: boolean;
  isGallery: boolean;
  icon: string;
}

export interface BoardPageContext {
  id: string;
  name: string;
  description: string;
  role: string;
  canEdit: boolean;
  canAdmin: boolean;
  isOwner: boolean;
  views: BoardViewTabContext[];
  activeView: BoardViewTabContext;
  tasks: TaskCardContext[];
  hasTasks: boolean;
  groupByName: string;
  hasFilters: boolean;
  filterSummary: string;
  hasSorts: boolean;
  sortSummary: string;
  canDrag: boolean;
  columns: TaskColumnContext[];
  calendarDays: CalendarDayContext[];
  calendarMonthLabel: string;
  previousMonthHref: string;
  nextMonthHref: string;
  todayMonthHref: string;
  hasDefaultTemplate: boolean;
  defaultTemplateName: string;
  newTaskTitle: string;
  newTaskDescription: string;
  newTaskStatus: string;
  newTaskStatusName: string;
  newTaskPriority: string;
  newTaskPriorityName: string;
  newTaskLabels: string;
  statusOptions: TaskOptionContext[];
  severityOptions: TaskOptionContext[];
  assignmentCount: number;
  completedAssignmentCount: number;
  undatedAssignmentCount: number;
  unestimatedAssignmentCount: number;
}

export interface TasksPageContext {
  query: string;
  tasks: TaskCardContext[];
  hasTasks: boolean;
  completedAssignmentCount: number;
  undatedAssignmentCount: number;
  unestimatedAssignmentCount: number;
}

export interface CommentContext {
  id: string;
  authorName: string;
  authorAvatar: AvatarContext;
  body: string;
  createdDisplay: string;
  canDelete: boolean;
}

export interface ChecklistContext {
  id: string;
  title: string;
  isCompleted: boolean;
}

export interface AttachmentContext {
  id: string;
  fileName: string;
  href: string;
  previewHref: string;
  sizeDisplay: string;
  isImage: boolean;
  isAudio: boolean;
  isVideo: boolean;
}

export interface MemberOptionContext {
  id: string;
  name: string;
  email: string;
  isSelected: boolean;
}

export interface TaskPropertyOptionContext {
  id: string;
  name: string;
  isSelected: boolean;
}

export interface TaskPropertyContext {
  id: string;
  name: string;
  value: string;
  inputValue: string;
  inputLabel: string;
  inputType: string;
  usesInput: boolean;
  usesSelect: boolean;
  usesMultiSelect: boolean;
  usesCheckbox: boolean;
  isChecked: boolean;
  options: TaskPropertyOptionContext[];
}

export interface TaskReminderContext {
  id: string;
  remindAt: string;
  remindAtDisplay: string;
  timeZone: string;
}

export interface TaskDetailPageContext {
  task: TaskCardContext;
  boardName: string;
  boardHref: string;
  creatorName: string;
  canEdit: boolean;
  canComment: boolean;
  isFollowing: boolean;
  followerCount: number;
  comments: CommentContext[];
  hasComments: boolean;
  checklist: ChecklistContext[];
  hasChecklist: boolean;
  attachments: AttachmentContext[];
  hasAttachments: boolean;
  members: MemberOptionContext[];
  properties: TaskPropertyContext[];
  hasProperties: boolean;
  reminders: TaskReminderContext[];
  notificationsEnabled: boolean;
}

export interface APIKeyPageItemContext {
  id: string;
  name: string;
  prefix: string;
  createdAt: string;
  expiresAt: string;
  lastUsedAt: string;
}

export interface APIKeysPageContext {
  keys: APIKeyPageItemContext[];
  hasKeys: boolean;
  apiBaseURL: string;
  createdKey: string;
  hasCreatedKey: boolean;
  error: string;
  hasError: boolean;
}

export interface BoardSettingsViewContext {
  id: string;
  name: string;
  typeName: string;
  groupBy: string;
  groupByName: string;
  isGroupedByStatus: boolean;
  isGroupedByPriority: boolean;
  filterField: string;
  filterValue: string;
  sortField: string;
  sortDirection: string;
  isAscending: boolean;
  isDescending: boolean;
}

export interface BoardMemberContext {
  id: string;
  name: string;
  email: string;
  role: string;
  avatar: AvatarContext;
}

export interface TemplateContext {
  id: string;
  name: string;
  title: string;
  isDefault: boolean;
}

export interface PropertyDefinitionContext {
  id: string;
  name: string;
  typeName: string;
  detail: string;
}

export interface TapTaskOptionContext {
  id: string;
  title: string;
  isSelected: boolean;
}

export interface TapActionContext {
  id: string;
  name: string;
  displayDescription: string;
  hasDisplayDescription: boolean;
  prefix: string;
  kind: string;
  kindName: string;
  isCreateTask: boolean;
  isUpdateTask: boolean;
  isEnabled: boolean;
  isActive: boolean;
  stateName: string;
  summary: string;
  status: string;
  statusName: string;
  severity: string;
  severityName: string;
  targetTaskID: string;
  targetTaskName: string;
  statusOptions: TaskOptionContext[];
  severityOptions: TaskOptionContext[];
  tasks: TapTaskOptionContext[];
  expiresAtInput: string;
  expiresAtLabel: string;
  maxUses: string;
  useCount: number;
  useLimitLabel: string;
  cooldownSeconds: number;
  lastUsedAt: string;
}

export interface TapExecutionContext {
  actionName: string;
  message: string;
  createdAt: string;
}

export interface BoardSettingsPageContext {
  id: string;
  name: string;
  description: string;
  firstViewHref: string;
  isOwner: boolean;
  isArchived: boolean;
  ownerName: string;
  ownerEmail: string;
  ownerAvatar: AvatarContext;
  views: BoardSettingsViewContext[];
  members: BoardMemberContext[];
  templates: TemplateContext[];
  properties: PropertyDefinitionContext[];
  statuses: TaskOptionContext[];
  severities: TaskOptionContext[];
  defaultTapStatus: string;
  defaultTapStatusName: string;
  defaultTapSeverity: string;
  defaultTapSeverityName: string;
  tapTasks: TapTaskOptionContext[];
  tapActions: TapActionContext[];
  tapExecutions: TapExecutionContext[];
  hasTapTasks: boolean;
  hasTapActions: boolean;
  hasTapExecutions: boolean;
  createdTapURL: string;
  createdTapURLByteCount: number;
  hasCreatedTapURL: boolean;
  tapError: string;
  hasTapError: boolean;
}

export interface AppPageContext {
  common: CommonPageContext;
  pageTitle: string;
  documentTitle: string;
  isOverview: boolean;
  isSemester: boolean;
  isBoard: boolean;
  isTasks: boolean;
  isActiveTasks: boolean;
  isArchivedTasks: boolean;
  isTaskDetail: boolean;
  isSettings: boolean;
  isProfileSettings: boolean;
  isAPIKeys: boolean;
  isBoardSettings: boolean;
  overview: OverviewPageContext | null;
  semester: SemesterPageContext | null;
  board: BoardPageContext | null;
  tasks: TasksPageContext | null;
  taskDetail: TaskDetailPageContext | null;
  settings: Record<string, never> | null;
  apiKeys: APIKeysPageContext | null;
  boardSettings: BoardSettingsPageContext | null;
}

export interface AuthConfiguration {
  oauthEnabled: boolean;
  oauthProviderName: string;
}

export interface TaskResponse {
  id: string;
  publicID: string;
  browserPath: string;
}

export interface BoardResponse {
  id: string;
  name: string;
}

export interface CreatedAPIKeyResponse {
  id: string;
  name: string;
  prefix: string;
  key: string;
  expiresAt: string | null;
  createdAt: string | null;
}

export interface TapTaskProperty {
  id: string;
  name: string;
  type: 'text' | 'number' | 'select' | 'multi_select' | 'date' | 'checkbox' | 'url' | 'email' | 'person';
  options: { id: string; name: string }[];
}

export interface TapTaskForm {
  status: string;
  priority: string;
  statuses: { id: string; name: string }[];
  priorities: { id: string; name: string }[];
  properties: TapTaskProperty[];
}

export interface TapPreparationResponse {
  actionName: string;
  actionDescription: string | null;
  kind: 'create_task' | 'update_task';
  task: TapTaskForm | null;
}

export interface TapExecutionResponse {
  actionName: string;
  actionDescription: string | null;
  message: string;
}
