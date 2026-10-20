Premailer::Rails.config.merge!(
  adapter: :nokogiri,
  generate_text_part: false,
  strategies: [:filesystem, :propshaft],
  # Keep the JSON-LD email markup (see EmailMarkupHelper).
  remove_scripts: false
)
