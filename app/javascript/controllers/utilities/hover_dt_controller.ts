import {Controller} from "@hotwired/stimulus";
import {GonConfig} from "../../gon_config";

interface TimePreferences {
    "time.use_24h": boolean;
    "time.use_iso8601": boolean;
}

const config = GonConfig.UserPreferences<TimePreferences>();

function getDisplayFormat(format: StaticFormatType, overrides: Intl.DateTimeFormatOptions = {}): Intl.DateTimeFormatOptions {
    const base = DISPLAY_FORMATS[format] ?? DISPLAY_FORMATS.datetime;
    const prefOverrides: Intl.DateTimeFormatOptions = {};

    if (config.has("time.use_24h")) {
        prefOverrides.hour12 = !config.get("time.use_24h");
    }

    return { ...base, ...prefOverrides, ...overrides };
}

type StaticFormatType = "datetime" | "date" | "short" | "time" | "timeNoSeconds";
type DynamicFormatType = "dotiw" | "adaptive" | "dotiw_smart";

// Supported display format types:
//   dotiw       – relative "distance of time in words" (e.g. "3 hours ago", "in 2 days")
//   datetime    – full localized date + time (default when format is set)
//   date        – localized long date only (e.g. "April 20, 2026")
//   short       – localized short date (e.g. "Apr 20, 2026")
//   time        – localized time only (e.g. "14:32:15 UTC")
//   adaptive    – time (HH:MM) if today, short date otherwise; good for compact badges
//   dotiw_smart - DOTIW up until one week ago, then short date.
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
        if (this.hasFormatValue && (format === "dotiw" || format === "adaptive" || format === "dotiw_smart")) {
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
        switch (format) {
            case "dotiw":
                return this.formatRelative(date);
            case "dotiw_smart":
                return this.formatRelativeSmart(date);
            case "adaptive":
                return this.formatAdaptive(date);
        }

        return date.toLocaleString(undefined, getDisplayFormat(format));
    }

    private formatAdaptive(date: Date): string {
        const now = new Date();
        const isToday = date.getFullYear() === now.getFullYear() &&
            date.getMonth() === now.getMonth() &&
            date.getDate() === now.getDate();

        return isToday
            ? date.toLocaleTimeString(undefined, getDisplayFormat("timeNoSeconds"))
            : date.toLocaleDateString(undefined, getDisplayFormat("short"));
    }

    private formatRelative(date: Date): string {
        const rtf = new Intl.RelativeTimeFormat(undefined, {numeric: "auto"});
        const diffMs = date.getTime() - Date.now();
        const diffSecs = Math.round(diffMs / 1000);
        const absSecs = Math.abs(diffSecs);

        if (-15 < diffSecs && diffSecs <= 0) return "just now";
        if (0 < diffSecs && diffSecs < 15) return "in a moment";
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

    private formatRelativeSmart(date: Date, cutoffDays: number = 7): string {
        const diffMs = date.getTime() - Date.now();
        const diffDays = Math.round(diffMs / 86_400_000);

        if (Math.abs(diffDays) < cutoffDays) {
            return this.formatRelative(date);
        } else {
            return this.formatDate(date, "short");
        }
    }
}