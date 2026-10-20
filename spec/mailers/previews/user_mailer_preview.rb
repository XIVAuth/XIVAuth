class UserMailerPreview < ActionMailer::Preview
  def reset_password_instructions
    UserMailer.reset_password_instructions(sample_user, "preview-token")
  end

  def confirmation_instructions
    UserMailer.confirmation_instructions(sample_user, "preview-token")
  end

  def reconfirmation_instructions
    user = sample_user
    user.unconfirmed_email = "new-address@example.com"

    UserMailer.confirmation_instructions(user, "preview-token", to: user.unconfirmed_email)
  end

  private def sample_user
    User.new(email: "preview@example.com", profile: User::Profile.new(display_name: "Preview User"))
  end
end
