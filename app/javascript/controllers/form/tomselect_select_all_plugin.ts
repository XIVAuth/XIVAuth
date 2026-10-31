import TomSelect from "tom-select";

type SelectAllOptions = {
    label?: string,
    clearLabel?: string,
};

TomSelect.define("select_all", function (this: TomSelect, options: SelectAllOptions = {}) {
    const label = options.label ?? "Select all";
    const clearLabel = options.clearLabel ?? "Clear";

    const makeButton = (text: string, onPress: () => void) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "btn btn-link btn-sm p-0";
        button.textContent = text;

        button.addEventListener("mousedown", (e) => {
            e.preventDefault();
            onPress();
            this.trigger("change", this.getValue());
            this.refreshOptions(false);
        });

        return button;
    };

    this.on("initialize", () => {
        const header = document.createElement("div");
        header.className = "ts-select-all d-flex justify-content-between px-2 py-1";

        header.appendChild(makeButton(label, () => this.addItems(Object.keys(this.options), true)));
        header.appendChild(makeButton(clearLabel, () => this.clear(true)));

        header.addEventListener("mousedown", (e) => e.preventDefault());

        this.dropdown.prepend(header);
    });
});
