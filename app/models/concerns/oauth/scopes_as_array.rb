module OAuth::ScopesAsArray
  def scopes
    get_scope_object(self[:scopes])
  end

  def scopes=(value)
    scope_obj = get_scope_object(value)

    attr_data = OAuth::AccessToken.attribute_types["scopes"]
    if attr_data.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array) && attr_data.type == :string
      self.write_attribute(:scopes, scope_obj.to_a)
    elsif OAuth::AccessToken.attribute_types["scopes"].type == :string
      self.write_attribute(:scopes, scope_obj.to_s)
    end
  end

  def scopes_string
    scopes = self[:scopes]

    if scopes.is_a?(Array)
      scopes.join(" ")
    else
      scopes
    end
  end

  def includes_scope?(*required_scopes)
    required_scopes.blank? || required_scopes.any? { |scope| scopes.exists?(scope.to_s) }
  end

  private def get_scope_object(input)
    if input.is_a?(Array)
      Doorkeeper::OAuth::Scopes.from_array(input)
    else
      Doorkeeper::OAuth::Scopes.from_string(input.to_s)
    end
  end
end
