import {RecursivePartial, TomOption, TomSettings} from "tom-select/dist/types/types";
import TomSelectController from "../form/tomselect_controller_base";
import {escape_html} from "tom-select/src/utils";

export default class IdentitySelectDropdownController extends TomSelectController {
    get user_settings(): RecursivePartial<TomSettings> {
        return {
            render: {
                item: this.renderItem,
                option: this.renderOption,
            },
            plugins: {
                'remove_button': {
                    title: 'Remove this item'
                },
                'clear_button': {},
            },
            searchField: ["identityName", "identityProvider"],
        };
    }

    renderItem(data: TomOption, escape: typeof escape_html): string {
        return "<div>" +
            `<i class='fab fa-${data.identityProvider} me-1 fa-fw'></i> ${escape(data.identityDisplayName)}` +
            "</div>";
    }

    renderOption(data: TomOption, escape: typeof escape_html): string {
        let render = "<div>" +
            `<span><i class='fab fa-${data.identityProvider} me-1 fa-fw'></i> ${data.identityDisplayName}</span>`;

        if (data.identityUsername != data.identityDisplayName) {
            render += ` <span class='very-small'>(@${escape(data.identityUsername)})</span>`;
        }

        render += "</div>"

        return render;
    }

    onItemAdd(value: (string | number), item: HTMLDivElement): void {
        if (value == "_all") {
            this.tomSelect!.clear(true);

            let items: string[] = [];
            for (let option of Object.values(this.tomSelect!.options)) {
                if (option.value != "_all") {
                    items.push(option.value);
                }
            }

            this.tomSelect!.addItems(items);
        }
    }
}