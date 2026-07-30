import '@fontsource-variable/geist';
import '@fontsource-variable/geist-mono';
import 'flatpickr/dist/flatpickr.css';
import './app.css';
import '@hotwired/turbo';
import { Application } from '@hotwired/stimulus';
import {
  Archive,
  ArrowDownUp,
  Bell,
  CalendarDays,
  Check,
  CheckSquare,
  ChevronDown,
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
  DatePickerController,
  DialogController,
  MenuController,
  SearchController,
  SidebarController,
  ThemeController,
  ToastController,
} from './controllers';

const application = Application.start();
application.register('board', BoardController);
application.register('date-picker', DatePickerController);
application.register('dialog', DialogController);
application.register('menu', MenuController);
application.register('search', SearchController);
application.register('sidebar', SidebarController);
application.register('theme', ThemeController);
application.register('toast', ToastController);

function renderIcons(): void {
  createIcons({
    icons: {
      Archive,
      ArrowDownUp,
      Bell,
      CalendarDays,
      Check,
      CheckSquare,
      ChevronDown,
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
