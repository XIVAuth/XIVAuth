class ThemeManager {
    userPreferenceTheme: string | null;

    constructor() {
        this.userPreferenceTheme = document.documentElement.getAttribute("data-bs-theme");
        if (this.userPreferenceTheme === "auto") {
            this.setTheme(this.getPreferredTheme());
        }

        window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", this.onColorSchemeChange.bind(this));
    }

    getPreferredTheme(): string {
        if (!window.matchMedia) return "light";
        return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    }

    setTheme(newTheme: string, saveTheme: boolean = false) {
        document.documentElement.setAttribute("data-bs-theme", newTheme);
    }

    onColorSchemeChange(event: MediaQueryListEvent) {
        let darkModeRequested = event.matches;

        if (this.userPreferenceTheme == "auto") {
            this.setTheme(darkModeRequested ? "dark" : "light");
        }
    }
}

if (window.matchMedia != undefined && document.documentElement.hasAttribute("data-bs-theme")) {
    new ThemeManager();
}