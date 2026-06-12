/// <reference types="cloudflare-turnstile" />
import {Controller} from "@hotwired/stimulus";
type RenderParameters = Turnstile.RenderParameters;

export default class LoginFormController extends Controller {
    static targets = ["webauthnChallenge", "webauthnResponse", "actionButton", "webauthnFeedback"];

    declare readonly webauthnChallengeTarget: HTMLInputElement;
    declare readonly webauthnResponseTarget: HTMLInputElement;
    declare readonly actionButtonTargets: HTMLButtonElement[] | undefined;
    declare readonly webauthnFeedbackTarget: HTMLDivElement;

    private discoveryAbortController: AbortController = new AbortController();

    async initialize() {

        this.initializeTurnstileChallenge();
    }

    async connect() {
        this.discoveryAbortController = new AbortController();
    }

    async disconnect() {
        this.discoveryAbortController.abort("disconnect");
        super.disconnect();
    }

    async webauthnRunConditional() {
        if (!await this.checkConditionalMediation()) {
            return;
        }

        let credential: PublicKeyCredential | null = null;
        try {
            let discovery = PublicKeyCredential.parseRequestOptionsFromJSON(JSON.parse(this.webauthnChallengeTarget.value));
            credential = await navigator.credentials.get({
                signal: this.discoveryAbortController.signal,
                publicKey: discovery,
                mediation: "conditional",
            }) as PublicKeyCredential | null;
        } catch (e: unknown) {
            // Ignore errors in discovery, as this is supposed to be a silent process.
            return;
        }

        if (credential && !(credential instanceof PublicKeyCredential)) {
            Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
        }

        if (credential) {
            this.webauthnResponseTarget.value = JSON.stringify(credential.toJSON());
            this.webauthnResponseTarget.form!.submit();
        }
    }

    webauthnAbort() {
        this.discoveryAbortController.abort("passwordLogin");
    }

    async webauthnManualDiscovery() {
        // stop conditional first, we don't need it anymore.
        this.discoveryAbortController.abort("manualWebauthn");

        let credential: PublicKeyCredential | null = null;
        try {
            let discovery = PublicKeyCredential.parseRequestOptionsFromJSON(JSON.parse(this.webauthnChallengeTarget.value));
            credential = await navigator.credentials.get({
                publicKey: discovery,
            }) as PublicKeyCredential | null;
        } catch (err: unknown) {
            console.error("WebAuthn manual discovery failed:", err);
            if (err instanceof DOMException && err.name === "NotAllowedError") {
                this.webauthnFeedbackTarget.innerText = "Your browser blocked an attempt to use a Passkey. " +
                    "Please make sure your security key is available and try again.";
                this.webauthnFeedbackTarget.parentElement?.classList.remove("d-none");
                return;
            }

            if (err instanceof DOMException && err.name === "NotSupportedError") {
                this.webauthnFeedbackTarget.innerText = "Your browser does not support WebAuthn. Please try again " +
                    "with a different browser.";
                this.webauthnFeedbackTarget.parentElement?.classList.remove("d-none");
                return;
            }
            return;
        }

        if (credential && !(credential instanceof PublicKeyCredential)) {
            Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
        }

        if (credential) {
            this.webauthnResponseTarget.value = JSON.stringify(credential.toJSON());
            this.webauthnResponseTarget.form!.submit();
        }
    }

    private initializeTurnstileChallenge() {
        const turnstileEl = this.element.querySelector('.cf-turnstile') as HTMLElement;
        let turnstileElData = Object.assign({}, turnstileEl.dataset) as unknown as RenderParameters;
        turnstileElData["before-interactive-callback"] = this.onTurnstileNeedsInteractive.bind(this);
        turnstileElData.callback = this.onTurnstileSuccess.bind(this);

        this.actionButtonTargets?.forEach(button => {
            if (button.innerText.trim().length > 0) {
                button.setAttribute("data-original-text", button.innerText);
                button.innerText = "Waiting for captcha...";
            }

            if (button.value.trim().length > 0) {
                button.setAttribute("data-original-value", button.value);
                button.value = "Waiting for captcha...";
            }

            button.disabled = true;
            button.classList.add('disabled');
        });

        turnstile.render(turnstileEl, turnstileElData);
    }

    private onTurnstileNeedsInteractive() {
        const turnstileEl = this.element.querySelector('.cf-turnstile') as HTMLElement;
        turnstileEl.classList.add('pt-2');
    }

    private onTurnstileSuccess() {
        this.webauthnRunConditional().then(); // faf

        this.actionButtonTargets?.forEach(button => {
            button.disabled = false;
            button.classList.remove('disabled');

            const originalText = button.getAttribute("data-original-text");
            if (originalText) {
                button.innerText = originalText;
                button.removeAttribute("data-original-text");
            }

            const originalValue = button.getAttribute("data-original-value");
            if (originalValue) {
                button.value = originalValue;
                button.removeAttribute("data-original-value");
            }
        })
    }


    private async checkConditionalMediation() {
        return window.PublicKeyCredential?.isConditionalMediationAvailable ||
            (await window.PublicKeyCredential?.isConditionalMediationAvailable());
    }
}
