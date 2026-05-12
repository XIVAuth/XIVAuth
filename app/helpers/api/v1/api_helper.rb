module Api::V1::ApiHelper
  SCOPE_SEPARATOR = ":".freeze

  # Test to see if a specific scope is authorized (or if the manage scope is present).
  # @param scope [string] The scope text to check
  # @param manage_allows [boolean] Whether the :manage scope grants permission to this check
  # @return [boolean] Returns true if the specified scope is authorized, false otherwise.
  def scope_authorized?(scope, manage_allows: true)
    scope_family = scope.split(SCOPE_SEPARATOR, 2)[0]

    return true if manage_allows && (doorkeeper_token.scopes.exists? "#{scope_family}:manage")

    doorkeeper_token.scopes.exists? scope
  end

  # Test to see if any child scope of a given parent is present (e.g. is any "user:*" scope granted)
  # @param parent_scope [string] The parent scope (e.g. "user") to check for.
  # @param excluded_children [Array<string>] Any excluded children that should not be considered valid for this check
  # @return [boolean] Returns true if any scope from the specified family is present, false otherwise.
  def any_child_scope?(parent_scope, excluded_children: [])
    doorkeeper_token.scopes.each do |scope|
      family, child = scope.split(SCOPE_SEPARATOR, 2)

      return true if family == parent_scope && !(excluded_children.include? child)
    end

    false
  end
end
