module PasswordStrengthValidatable
  extend ActiveSupport::Concern

  MIN_PASSWORD_SCORE = Rails.env.production? ? 3 : 0

  included do
    class_attribute :zxcvbn_user_inputs, default: [], instance_predicate: false
    class_attribute :zxcvbn_static_inputs, default: [], instance_predicate: false
    validate :strong_password, unless: :skip_password_complexity?
  end

  private

  def skip_password_complexity?
    !password_required? || Rails.env.test?
  end

  def strong_password
    score = zxcvbn_score
    return if score >= MIN_PASSWORD_SCORE

    errors.add(:password, :weak_password, score: score, min_password_score: MIN_PASSWORD_SCORE)
  end

  def zxcvbn_score
    weak_words = zxcvbn_user_inputs.flat_map do |field|
      value = public_send(field).to_s
      [value, *value.split(/[[:^word:]_]/)]
    end + zxcvbn_static_inputs

    Zxcvbn::Tester.new.test(password.to_s, weak_words.reject(&:empty?)).score
  end
end
