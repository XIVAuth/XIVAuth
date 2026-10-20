Premailer::Rails.config.merge!(
  adapter: :nokogiri,
  generate_text_part: false,
  strategies: [:filesystem, :propshaft]
)
