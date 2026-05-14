import {Application} from "@hotwired/stimulus";
import {definitions} from "stimulus:./";

declare global {
    interface Window {
        Stimulus: Application;
        gon: {
            app_env: string;
            user_preferences?: Record<string, unknown>;
        }
    }
}

const application = Application.start();
application.load(definitions);

// Configure Stimulus development experience
application.debug = window.gon.app_env === "development";

window.Stimulus = application;

export {application};
