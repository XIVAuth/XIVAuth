import {RecursivePartial, TomOption, TomSettings} from "tom-select/src/types";
import {escape_html} from "tom-select/src/utils";
import TomSelectController from "../form/tomselect_controller_base";

export default class CharacterSelectDropdownContoller extends TomSelectController {
    get user_settings() {
        let settings: RecursivePartial<TomSettings> = {
            render: {
                option: this.renderOption,
                item: this.renderItem,
                no_results: this.renderNoResults,
            },
            searchField: ["characterName"]
        };

        if (this.element.multiple) {
            settings.plugins = {
                'select_all': {
                    label: 'Select all characters'
                },
                'checkbox_options': {},
                'summary': {
                    threshold: 1,
                    format: (count: number) => `${count} ${count == 1 ? 'character' : 'characters'} selected`,
                    icon: (data: TomOption, escape: typeof escape_html) =>
                        `<img src="${escape(data.characterAvatar)}" alt="">`,
                },
                'no_backspace_delete': {},
            };
        }

        return settings;
    }

    renderOption(data: TomOption, escape: typeof escape_html): string {
        return "<div class='d-flex flex-row align-items-center'>" +
            `<img src="${data.characterAvatar}" class="me-2 rounded" style="width: 48px; height: 48px;">` +
            `<div class='ps-2'>` +
            `<span class='fs-6'>${escape(data.characterName)}</span><br/>` +
            `<span class='small'>${escape(data.characterWorld)} [${escape(data.characterDatacenter)}]</span>` +
            "</div>" +
            "</div>";
    }

    renderItem(data: TomOption, escape: typeof escape_html): string {
        return "<div class='d-flex flex-row align-items-center'>" +
            `<img src="${data.characterAvatar}" class="me-2 rounded" style="width: 48px; height: 48px;">` +
            `<div class='ps-2'>` +
            `<span class='fs-6'>${escape(data.characterName)}</span><br/>` +
            `<span class='small'>${escape(data.characterWorld)} [${escape(data.characterDatacenter)}]</span>` +
            "</div>" +
            "</div>";
    }

    renderNoResults(data: TomOption, escape: typeof escape_html): string {
        return `<div class='text-center'>Couldn't find a character name matching "${data.input}"</div>`;
    }
}