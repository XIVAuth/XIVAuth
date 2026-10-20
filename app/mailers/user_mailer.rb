class UserMailer < Devise::Mailer
  default from: "XIVAuth <noreply@xivauth.net>"

  def reset_password_instructions(record, token, opts = {})
    @new_reset_url = begin_user_recovery_url
    @link_ttl = Devise.reset_password_within.inspect

    super(record, token, { template_name: "reset_password" }.merge(opts))
  end

  # Devise sends reconfirmations (email changes) through this same action, with +opts[:to]+ set to the unconfirmed
  # email address.
  def confirmation_instructions(record, token, opts = {})
    defaults = if record.pending_reconfirmation?
      { template_name: "email_change_request", subject: I18n.t("devise.mailer.reconfirmation_instructions.subject") }
    else
      { template_name: "welcome" }
    end

    super(record, token, defaults.merge(opts))
  end
end
