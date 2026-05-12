module AttributeHelper
  # Mark attributes in a record as explicitly managed by ActiveRecord.
  def attr_activerecord(*attributes)
    defined = []
    defined << attr_ar_getter(*attributes)
    defined << attr_ar_setter(*attributes)

    defined
  end

  # Mark record getters as explicitly managed by ActiveRecord.
  def attr_ar_getter(*attributes)
    defined = []
    attributes.each do |attribute|
      method = attribute.to_s
      define_method(method) do
        self[attribute]
      end
      defined << method
    end

    defined
  end

  # Mark record setters as explicitly managed by ActiveRecord.
  def attr_ar_setter(*attributes)
    defined = []
    attributes.each do |attribute|
      method = "#{attribute}="
      define_method(method) do |v|
        self[attribute] = v
      end
      defined << method
    end

    defined
  end
end
