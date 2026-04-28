import {Controller} from "@hotwired/stimulus";

type StaticFormatType = "datetime" | "date" | "short" | "time" | "timeNoSeconds";
type DynamicFormatType = "dotiw" | "adaptive";

// Supported display format types:
//   dotiw    – relative "distance of time in words" (e.g. "3 hours ago", "in 2 days")
//   datetime – full localized date + time (default when format is set)
//   date     – localized long date only (e.g. "April 20, 2026")
//   short    – localized short date (e.g. "Apr 20, 2026")
//   time     – localized time only (e.g. "14:32:15 UTC")
//   adaptive – time (HH:MM) if today, short date otherwise; good for compact badges
type FormatType = StaticFormatType | DynamicFormatType;

const DOTIW_REFRESH_MS = 1_000;

const FULL_FORMAT: Intl.DateTimeFormatOptions = {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    timeZoneName: "short",
};

const DISPLAY_FORMATS: Record<StaticFormatType, Intl.DateTimeFormatOptions> = {
    datetime: {
        month: "long",
        day: "numeric",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
    },
    date: {
        month: "long",
        day: "numeric",
        year: "numeric",
    },
    short: {
        month: "short",
        day: "numeric",
        year: "numeric",
    },
    time: {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
    },
    timeNoSeconds: {
        hour: "2-digit",
        minute: "2-digit",
    }
};
export default class HoverDateTimeController extends Controller<HTMLElement> {
    static values = {
        ts: Number,
        format: String,
    };

    declare readonly hasTsValue: boolean;
    declare tsValue: number;
    declare readonly hasFormatValue: boolean;
    declare formatValue: string;

    private refreshTimer: ReturnType<typeof setInterval> | null = null;

    connect() {
        if (!this.hasTsValue) return;
        this.render();

        const format = this.formatValue as FormatType;
        if (this.hasFormatValue && (format === "dotiw" || format === "adaptive")) {
            this.refreshTimer = setInterval(() => this.render(), DOTIW_REFRESH_MS);
        }
    }

    disconnect() {
        if (this.refreshTimer !== null) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }

    private render() {
        const date = new Date(this.tsValue * 1000);

        if (this.formatValue != "datetime") {
            this.element.title = date.toLocaleString(undefined, FULL_FORMAT);
        }

        if (!this.hasFormatValue) return;

        this.element.textContent = this.formatDate(date, this.formatValue as FormatType);
    }

    private formatDate(date: Date, format: FormatType): string {
        if (format === "dotiw") {
            return this.formatRelative(date);
        }

        if (format === "adaptive") {
            return this.formatAdaptive(date);
        }

        const options = DISPLAY_FORMATS[format] ?? DISPLAY_FORMATS.datetime;
        return date.toLocaleString(undefined, options);
    }

    private formatAdaptive(date: Date): string {
        const now = new Date();
        const isToday = date.getFullYear() === now.getFullYear() &&
            date.getMonth() === now.getMonth() &&
            date.getDate() === now.getDate();

        return isToday
            ? date.toLocaleTimeString(undefined, DISPLAY_FORMATS.timeNoSeconds)
            : date.toLocaleDateString(undefined, DISPLAY_FORMATS.short);
    }

    private formatRelative(date: Date): string {
        const rtf = new Intl.RelativeTimeFormat(undefined, {numeric: "auto"});
        const diffMs = date.getTime() - Date.now();
        const diffSecs = Math.round(diffMs / 1000);
        const absSecs = Math.abs(diffSecs);

        if (absSecs < 15) return "just now";
        if (absSecs < 60) return rtf.format(diffSecs, "second");

        const diffMins = Math.round(diffMs / 60_000);
        if (Math.abs(diffMins) < 60) return rtf.format(diffMins, "minute");

        const diffHours = Math.round(diffMs / 3_600_000);
        if (Math.abs(diffHours) < 24) return rtf.format(diffHours, "hour");

        const diffDays = Math.round(diffMs / 86_400_000);
        if (Math.abs(diffDays) < 7) return rtf.format(diffDays, "day");

        const diffWeeks = Math.round(diffMs / 604_800_000);
        if (Math.abs(diffWeeks) < 5) return rtf.format(diffWeeks, "week");

        const diffMonths = Math.round(diffMs / 2_592_000_000);
        if (Math.abs(diffMonths) < 12) return rtf.format(diffMonths, "month");

        const diffYears = Math.round(diffMs / 31_536_000_000);
        return rtf.format(diffYears, "year");
    }
}