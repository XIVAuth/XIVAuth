import {RecursivePartial, TomOption, TomSettings} from "tom-select/src/types";
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
                'checkbox_options': {},
                'select_all': {
                    label: 'Select all identities'
                },
                'summary': {
                    threshold: 1,
                    format: (count: number) => `${count} ${count == 1 ? 'identity' : 'identities'} selected`,
                    icon: (data: TomOption, escape: typeof escape_html) =>
                        `<span class="ts-stack-brand bg-brand-${escape(data.identityProvider)}">` +
                        `<i class="fab fa-${escape(data.identityProvider)}"></i></span>`,
                },
                'no_backspace_delete': {},
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
            render += `<span class='very-small ps-1'>(@${escape(data.identityUsername)})</span>`;
        }

        render += "</div>"

        return render;
    }
}