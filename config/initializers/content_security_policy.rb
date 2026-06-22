require "environment_info"

# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self, "https://cdn.xivauth.net/"
    policy.font_src        :self, :https, :data
    policy.img_src         :self, :https, :data, :blob, "https://cdn.xivauth.net/"
    policy.object_src      :none
    policy.script_src      :self, "https://challenges.cloudflare.com/", "https://*.cloudflareinsights.com/"
    policy.frame_src       :self, "https://challenges.cloudflare.com/"
    policy.style_src       :self, :unsafe_inline
    policy.base_uri        :none
    policy.frame_ancestors :none
    policy.connect_src     :self, "https://*.sentry-cdn.com/", "https://*.sentry.io/",
                           "https://*.cloudflareinsights.com/", "https://challenges.cloudflare.com/"

    # We can't use a form_action policy because Chrome is annoying: https://github.com/w3c/webappsec-csp/issues/8
    # Since Chrome will follow redirects, this causes breaks on inbound (and outbound) OAuth, so it's better to just
    # not. SSL and script_src should protect things much better.

    if (csp_base_uri = Rails.application.credentials.dig(:sentry, :csp_report_uri))
      policy.report_uri csp_base_uri +
                        "&sentry_environment=#{EnvironmentInfo.environment}" \
                        "&sentry_release=#{EnvironmentInfo.commit_hash}"
    end
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.hex(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true

  # Report violations without enforcing the policy.
  config.content_security_policy_report_only = true
end
