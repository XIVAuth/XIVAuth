import {WebauthnControllerBase} from "../webauthn_base";

export default class WebauthnMFAController extends WebauthnControllerBase {
    async authenticate(event: PointerEvent) {
        event.preventDefault();

        let discovery = PublicKeyCredential.parseRequestOptionsFromJSON(JSON.parse(this.challengeTarget.value));
        let credential = await navigator.credentials.get({publicKey: discovery}) as PublicKeyCredential | null;

        // Hack for password managers: coerce this to a PublicKeyCredential
        if (credential && !(credential instanceof PublicKeyCredential)) {
            Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
            console.warn("Forced MFA credential to be a PublicKeyCredential! Webauthn logins may fail!")
        }
        
        if (credential) {
            this.responseTarget.value = JSON.stringify(credential.toJSON());
            (event.target as HTMLButtonElement).form?.submit();
        }
    }
}