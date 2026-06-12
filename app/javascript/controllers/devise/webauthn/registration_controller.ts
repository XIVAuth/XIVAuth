import {WebauthnControllerBase} from "../webauthn_base";


export default class WebauthnRegistrationController extends WebauthnControllerBase {
    static targets = ["challenge", "response", "feedback", "requestResidentKey"];

    declare readonly feedbackTarget: HTMLDivElement;
    declare readonly requestResidentKeyTarget: HTMLInputElement;

    async register(event: SubmitEvent) {
        if (this.responseTarget.value != "") {
            // The webauthn credential has already been grabbed, so no more waiting.
            return;
        }

        event.preventDefault();

        let credential: PublicKeyCredential | null = null;

        let challenge = this.buildRegistrationRequest(this.requestResidentKeyTarget.checked ? "required" : "discouraged");

        try {
            let creationOptions = PublicKeyCredential.parseCreationOptionsFromJSON(challenge);
            credential = await navigator.credentials.create({
                publicKey: creationOptions,
            }) as PublicKeyCredential | null;
        } catch (err: unknown) {
            if (err instanceof DOMException && err.name === "NotAllowedError") {
                this.feedbackTarget.innerText = "Your browser blocked an attempt to register a security key. Please " +
                    "make sure you have one available and try again.";
                this.feedbackTarget.classList.remove("d-none");
                return;
            }

            if (err instanceof DOMException && err.name === "NotSupportedError") {
                this.feedbackTarget.innerText = "Your browser does not support WebAuthn. Please try again with a " +
                    "different browser.";
                this.feedbackTarget.classList.remove("d-none");
                return;
            }

            throw err;
        }

        if (credential && !(credential instanceof PublicKeyCredential)) {
            Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
        }

        if (credential) {
            this.responseTarget.value = JSON.stringify(credential.toJSON());
            (event.target as HTMLFormElement).requestSubmit();
        }
    }

    async toggleResidentKey(event: InputEvent) {
        const target = event.target as HTMLInputElement;
        const updatedChallenge = this.buildRegistrationRequest(target.checked ? "preferred" : "discouraged");

        this.challengeTarget.value = JSON.stringify(updatedChallenge);
    }

    private buildRegistrationRequest(residentKey: ("discouraged" | "preferred" | "required")) {
        let challenge = JSON.parse(this.challengeTarget.value);
        challenge["authenticatorSelection"] ||= {};
        challenge["authenticatorSelection"]["residentKey"] = residentKey;

        return challenge;
    }
}