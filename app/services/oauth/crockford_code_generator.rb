require "utilities/crockford"

class OAuth::CrockfordCodeGenerator
  def self.generate
    Crockford.generate(length: 8)
  end
end
