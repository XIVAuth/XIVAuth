import {WebauthnControllerBase} from "../webauthn_base";
import * as WebAuthnJSON from "@github/webauthn-json";
import {PublicKeyCredentialWithAttestationJSON} from "@github/webauthn-json";


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

        let credential: PublicKeyCredentialWithAttestationJSON;

        let challenge = this.buildRegistrationRequest(this.requestResidentKeyTarget.checked ? "required" : "discouraged");

        try {
            // FIXME: Bug in certain password managers where they don't support toJSON on the response.
            credential = await WebAuthnJSON.create({
                "publicKey": challenge
            });
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

        this.responseTarget.value = JSON.stringify(credential);
        (event.target as HTMLFormElement).requestSubmit();
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