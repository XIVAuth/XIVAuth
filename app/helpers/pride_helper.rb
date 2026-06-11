module PrideHelper
  PRIDE_FLAGS = %i[
    rainbow transgender bisexual lesbian asexual gay demi nonbinary pansexual
  ].freeze

  def current_pride_flag_class(mode = nil)
    if params[:_debug_force_flag].present? && PRIDE_FLAGS.include?(params[:_debug_force_flag].to_sym)
      flag = params[:_debug_force_flag].to_sym
    elsif current_user.present? && current_user.preferences.pride_flag.present?
      user_flag = current_user.preferences.pride_flag.to_sym

      flag = user_flag unless user_flag == :random
    end

    flag ||= PRIDE_FLAGS[request.uuid.hash.abs % PRIDE_FLAGS.length]

    flag_class = "pride-brand--#{flag}"
    flag_class += "-#{mode}" if mode.present?
    flag_class
  end
end
