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
  KeyRound,
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
  ColorPickerController,
  CompletionController,
  DatePickerController,
  DialogController,
  FileFieldController,
  MenuController,
  PropertyDefinitionController,
  SearchController,
  SidebarController,
  TaskPageController,
  TaskPreviewController,
  TapActionFormController,
  TapProvisionController,
  ThemeController,
  ToastController,
} from './controllers';

const application = Application.start();
application.register('board', BoardController);
application.register('color-picker', ColorPickerController);
application.register('completion', CompletionController);
application.register('date-picker', DatePickerController);
application.register('dialog', DialogController);
application.register('file-field', FileFieldController);
application.register('menu', MenuController);
application.register('property-definition', PropertyDefinitionController);
application.register('search', SearchController);
application.register('sidebar', SidebarController);
application.register('task-page', TaskPageController);
application.register('task-preview', TaskPreviewController);
application.register('tap-action-form', TapActionFormController);
application.register('tap-provision', TapProvisionController);
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
      KeyRound,
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
