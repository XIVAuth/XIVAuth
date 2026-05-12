require "contextual_logger/formatters"
require "semantic_logger"

class ContextualLogger::Formatters::ColorFormatter < SemanticLogger::Formatters::Color
  def named_tags
    named_tags = log.named_tags.clone
    named_tags.delete(:_mdc)
    return if named_tags.blank?

    list = []
    named_tags.each_pair { |name, value| list << "#{name}: #{value}" }
    "{#{list.join(', ')}}"
  end
end
