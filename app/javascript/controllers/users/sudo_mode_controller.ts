import {Controller} from "@hotwired/stimulus";

export default class SudoModeController extends Controller<HTMLElement> {
    static targets = ["challenge", "response", "keyButton"];
    static values = {autoSubmit: {type: Boolean, default: true}};

    declare readonly challengeTarget: HTMLInputElement;
    declare readonly responseTarget: HTMLInputElement;
    declare readonly keyButtonTarget: HTMLButtonElement;
    declare readonly autoSubmitValue: boolean;

    async authenticate(event: Event) {
        event.preventDefault();

        let options = PublicKeyCredential.parseRequestOptionsFromJSON(JSON.parse(this.challengeTarget.value));
        let credential = await navigator.credentials.get({publicKey: options}) as PublicKeyCredential | null;

        // Hack for password managers: coerce this to a PublicKeyCredential
        if (credential && !(credential instanceof PublicKeyCredential)) {
            Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
        }

        if (!credential) return;

        this.responseTarget.value = JSON.stringify(credential.toJSON());

        if (this.autoSubmitValue) {
            this.responseTarget.form?.requestSubmit();
        } else {
            this.keyButtonTarget.disabled = true;
            this.keyButtonTarget.innerHTML = `<i class="bi bi-check-lg"></i> Security Key Ready`;
        }
    }
}
