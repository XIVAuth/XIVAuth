import * as Sentry from "@sentry/browser";


// Borrowed from https://github.com/odichat/odichat/blob/main/app/javascript/sentry.js
class SentryDebugger {
    feedbackWidget?: any;

    setup() {
        const sentryData = window.gon.sentry;

        if (sentryData == null || sentryData.dsn == null) {
            return;
        }

        if (sentryData.user) {
            Sentry.setUser(sentryData.user);
        }

        Sentry.init({
            dsn: sentryData.dsn,
            environment: sentryData.environment,
            sendDefaultPii: true,
            // Backend uses OTel's W3C propagators, so send traceparent alongside sentry-trace.
            propagateTraceparent: true,
            integrations: [
                Sentry.feedbackIntegration({
                    autoInject: false,
                    colorScheme: "system",
                    useSentryUser: {
                        name: "username",
                    },
                }),
            ]
        });

        this.feedbackWidget = Sentry.getFeedback();
        this.mountWidget();

        document.addEventListener("turbo:render", () => {
            requestAnimationFrame(this.mountWidget.bind(this));
        })
    }

    mountWidget() {
        if (this.feedbackWidget == null) {
            return;
        }

        this.feedbackWidget.remove();
        this.feedbackWidget.createWidget();
    }
}

declare global {
    interface Window {
        Sentry: typeof Sentry;

        gon: {
            sentry?: {
                dsn: string;
                environment: string;
                user?: {
                    id: number;
                    username: string;
                }
            }
        }
    }
}

window.Sentry = Sentry;
new SentryDebugger().setup();