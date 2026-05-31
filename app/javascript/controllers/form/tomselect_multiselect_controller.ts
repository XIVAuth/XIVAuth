import TomSelectController from "./tomselect_controller_base";
import {RecursivePartial, TomSettings} from "tom-select/src/types";

export default class TomSelectMultiselectController extends TomSelectController {
    get user_settings(): RecursivePartial<TomSettings> {
        return {
            plugins: ["remove_button"],
            persist: false,
            create: false,
        };
    }
}