import TomSelect from "tom-select";
import {TomOption} from "tom-select/src/types";
import {escape_html} from "tom-select/utils";

type SummaryOptions = {
    threshold?: number,
    format?: (count: number) => string,
    // HTML for a single item's icon in the summary stack; omit to show text only
    icon?: (data: TomOption, escape: typeof escape_html) => string,
    maxIcons?: number,
};

TomSelect.define("summary", function (this: TomSelect, options: SummaryOptions = {}) {
    const threshold = options.threshold ?? 2;
    const format = options.format ?? ((count: number) => `${count} selected`);
    const maxIcons = options.maxIcons ?? 3;

    // span, not div: Tom Select styles every `.ts-control > div` in multi mode as an item chip
    const summary = document.createElement("span");
    summary.className = "ts-summary";

    const stack = document.createElement("span");
    stack.className = "ts-stack";

    const text = document.createElement("span");
    text.className = "ts-summary-text";

    if (options.icon) summary.appendChild(stack);
    summary.appendChild(text);

    const renderStack = () => {
        const shown = this.items.slice(0, maxIcons);
        const overflow = this.items.length - shown.length;

        let html = shown
            .map((value) => this.options[value])
            .filter((data) => data)
            .map((data) => `<span class="ts-stack-icon">${options.icon!(data, escape_html)}</span>`)
            .join("");

        if (overflow > 0) {
            html += `<span class="ts-stack-icon ts-stack-more">+${overflow}</span>`;
        }

        stack.innerHTML = html;
    };

    const update = () => {
        const count = this.items.length;

        this.wrapper.classList.toggle("ts-summarized", count > threshold);
        text.textContent = format(count);
        if (options.icon) renderStack();
    };

    this.on("initialize", () => {
        this.control.insertBefore(summary, this.control_input);
        update();
    });

    this.on("item_add", update);
    this.on("item_remove", update);
    this.on("clear", update);
});
