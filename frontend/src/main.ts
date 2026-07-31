import '@fontsource-variable/rubik';
import '@fontsource-variable/geist-mono';
import 'flatpickr/dist/flatpickr.css';
import './app.css';
import '@hotwired/turbo';
import { Application } from '@hotwired/stimulus';
import {
  Archive,
  ArrowDownUp,
  ArrowUpRight,
  Bell,
  CalendarDays,
  Check,
  CheckSquare,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Circle,
  Columns3,
  Copy,
  Download,
  Filter,
  Folder,
  GalleryHorizontalEnd,
  House,
  LayoutDashboard,
  ListChecks,
  LogOut,
  Menu,
  MessageSquare,
  Moon,
  MoreHorizontal,
  PanelLeft,
  Paperclip,
  Plus,
  Search,
  Settings,
  Sun,
  Table2,
  Tag,
  Upload,
  User,
  Users,
  X,
  createIcons,
} from 'lucide';
import {
  BoardController,
  ChecklistController,
  CompletionController,
  DatePickerController,
  DialogController,
  FileFieldController,
  MarkdownController,
  MenuController,
  PropertyDefinitionController,
  SearchController,
  SidebarController,
  TaskPreviewController,
  ThemeController,
  ToastController,
} from './controllers';

const application = Application.start();
application.register('board', BoardController);
application.register('checklist', ChecklistController);
application.register('completion', CompletionController);
application.register('date-picker', DatePickerController);
application.register('dialog', DialogController);
application.register('file-field', FileFieldController);
application.register('markdown', MarkdownController);
application.register('menu', MenuController);
application.register('property-definition', PropertyDefinitionController);
application.register('search', SearchController);
application.register('sidebar', SidebarController);
application.register('task-preview', TaskPreviewController);
application.register('theme', ThemeController);
application.register('toast', ToastController);

function renderIcons(): void {
  createIcons({
    icons: {
      Archive,
      ArrowDownUp,
      ArrowUpRight,
      Bell,
      CalendarDays,
      Check,
      CheckSquare,
      ChevronDown,
      ChevronLeft,
      ChevronRight,
      Circle,
      Columns3,
      Copy,
      Download,
      Filter,
      Folder,
      GalleryHorizontalEnd,
      House,
      LayoutDashboard,
      ListChecks,
      LogOut,
      Menu,
      MessageSquare,
      Moon,
      MoreHorizontal,
      PanelLeft,
      Paperclip,
      Plus,
      Search,
      Settings,
      Sun,
      Table2,
      Tag,
      Upload,
      User,
      Users,
      X,
    },
  });
}

document.addEventListener('turbo:load', renderIcons);
document.addEventListener('turbo:frame-load', renderIcons);
renderIcons();
