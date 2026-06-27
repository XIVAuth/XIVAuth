import {Controller} from "@hotwired/stimulus";

const TOGGLES = `input[type="radio"], input[type="checkbox"]`;

export default class ToggleCategoryController extends Controller {
    static values = {behavior: {type: String, default: "hide"}}

    declare readonly behaviorValue: string;

    connect() {
        this.refresh();
    }

    onChange(event: Event) {
        const input = event.currentTarget as HTMLInputElement;
        const value = this.valueOf(input);
        if (!value) return;

        if (input.type === "radio") {
            this.controlled().forEach(el => this.deactivate(el));
            this.controlledFor(value).forEach(el => this.activate(el));
        } else if (input.type === "checkbox") {
            this.controlledFor(value).forEach(el =>
                input.checked ? this.activate(el) : this.deactivate(el)
            );
        }
    }

    private refresh() {
        this.controlled().forEach(el => this.deactivate(el));
        this.element.querySelectorAll<HTMLInputElement>(`${TOGGLES}`)
            .forEach(input => {
                if (!input.checked) return;
                const value = this.valueOf(input);
                if (value) this.controlledFor(value).forEach(el => this.activate(el));
            });
    }

    private activate(el: HTMLElement) {
        if (this.behaviorFor(el) === "hide") {
            el.classList.remove("d-none");
        } else if (el instanceof HTMLInputElement) {
            el.disabled = false;
        }
    }

    private deactivate(el: HTMLElement) {
        if (this.behaviorFor(el) === "hide") {
            el.classList.add("d-none");
        } else if (el instanceof HTMLInputElement) {
            el.disabled = true;
        }
    }

    private behaviorFor(el: HTMLElement): string {
        return el.getAttribute(this.dataAttr("behavior")) ?? this.behaviorValue;
    }

    private valueOf(el: Element): string | null {
        return el.getAttribute(this.dataAttr("value"));
    }

    private controlled(): HTMLElement[] {
        return Array.from(this.element.querySelectorAll<HTMLElement>(
            `[${this.dataAttr("value")}]:not(${TOGGLES})`
        ));
    }

    private controlledFor(value: string): HTMLElement[] {
        return Array.from(this.element.querySelectorAll<HTMLElement>(
            `[${this.dataAttr("value")}="${value}"]:not(${TOGGLES})`
        ));
    }

    private dataAttr(name: string): string {
        return `data-${this.identifier}-${name}`;
    }
}
