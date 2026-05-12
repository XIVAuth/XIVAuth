module PrideHelper
  PRIDE_FLAGS = %w[
    rainbow transgender bisexual lesbian asexual gay demi nonbinary pansexual
  ].freeze

  def current_pride_flag_class(mode = nil)
    # Check for debug override via query parameter
    if params[:_debug_force_flag].present? && PRIDE_FLAGS.include?(params[:_debug_force_flag])
      flag = params[:_debug_force_flag]
    else
      # Use the request UUID to deterministically select a flag
      # This ensures the same flag is shown throughout a request
      index = request.uuid.hash.abs % PRIDE_FLAGS.length
      flag = PRIDE_FLAGS[index]
    end

    flag_class = "pride-brand--#{flag}"

    # Append mode suffix if specified (e.g., "-light" or "-dark")
    flag_class += "-#{mode}" if mode.present?

    flag_class
  end
end
