import {Controller} from "@hotwired/stimulus"
import zxcvbn from "zxcvbn";

export default class PasswordStrengthController extends Controller {
    static targets = ["password", "confirm", "tips", "warning", "meterInner", "meter", "strength"];
    static values = {
        minScore: Number,
    }

    declare readonly passwordTarget: HTMLInputElement;
    declare readonly confirmTarget: HTMLInputElement;
    declare readonly tipsTarget: HTMLUListElement;
    declare readonly warningTarget: HTMLDivElement;
    declare readonly meterInnerTarget: HTMLDivElement;
    declare readonly meterTarget: HTMLDivElement;
    declare readonly strengthTarget: HTMLDivElement;

    declare minScoreValue: number;
    declare readonly hasMinScoreValue: boolean;

    static STRENGTH_NAMES: { [key: number]: string } = {
        0: "Extremely Weak",
        1: "Very Weak",
        2: "Weak",
        3: "Decent",
        4: "Strong"
    }

    connect() {
        this.calc();
    }

    calc() {
        this.onConfirm();

        if (this.passwordTarget.value === "") {
            this.strengthTarget.parentElement?.classList.add('d-none');
        } else {
            this.strengthTarget.parentElement?.classList.remove('d-none');
        }

        let result = zxcvbn(this.passwordTarget.value);
        let strengthValue = this.strengthPercentage(result.guesses_log10);
        
        this.strengthTarget.innerText = this.strengthName(result.score);
        this.strengthTarget.className = this.strengthTarget.className.replace(/\btext-.+\b/, this.scoreTextClass(result.score))

        this.meterInnerTarget.className = this.meterInnerTarget.className.replace(/\bbg-.+\b/, this.scoreGaugeClass(result.score));
        this.meterInnerTarget.style['width'] = `${strengthValue}%`;

        this.tipsTarget.innerHTML = "";
        if (result.feedback.warning) {
            let el = document.createElement("li");
            el.classList.add("text-warning-emphasis", "fw-bold");
            el.innerText = result.feedback.warning;

            this.tipsTarget.appendChild(el);
        }

        result.feedback.suggestions.forEach(tip => {
            let el = document.createElement("li");
            el.innerText = tip;

            this.tipsTarget.appendChild(el);
        })
    }

    onConfirm() {
        if (this.confirmTarget.value === "") {
            if (this.passwordTarget.value === "") {
                this.confirmTarget.classList.remove('is-invalid');
            }

            return;
        }

        if (this.passwordTarget.value !== this.confirmTarget.value) {
            this.confirmTarget.classList.add('is-invalid');
        } else {
            this.confirmTarget.classList.remove('is-invalid');
        }
    }

    scoreGaugeClass(score: number) {
        if (score === 4 || (score > this.minScoreValue)) return `bg-success`;
        return (score < this.minScoreValue) ? `bg-danger` : `bg-warning`;
    }

    scoreTextClass(score: number) {
        if (score === 4 || (score > this.minScoreValue)) return 'text-success';
        return (score < this.minScoreValue) ? 'text-danger' : 'text-warning-emphasis';
    }

    strengthPercentage(guessCount: number) {
        // calculated such that a password of score 3 (10^8) will be in the middle.
        return Math.min(guessCount * (1 / 16) * 100, 100);
    }

    strengthName(score: number) {
        if (score < this.minScoreValue) return "Too Weak";

        return `${PasswordStrengthController.STRENGTH_NAMES[score]} Password`;
    }

    togglePassword(event: Event) {
        event.preventDefault();
        const button = event.currentTarget as HTMLButtonElement;
        const inputGroup = button.parentElement;
        if (!inputGroup) return;

        const field = inputGroup.querySelector('input[type="password"], input[type="text"]') as HTMLInputElement;
        if (!field) return;

        const icon = button.querySelector('i');
        if (!icon) return;

        if (field.type === 'password') {
            field.type = 'text';
            icon.classList.remove('bi-eye');
            icon.classList.add('bi-eye-slash');
            button.setAttribute('aria-label', 'Hide password');
        } else {
            field.type = 'password';
            icon.classList.remove('bi-eye-slash');
            icon.classList.add('bi-eye');
            button.setAttribute('aria-label', 'Show password');
        }
    }
}
