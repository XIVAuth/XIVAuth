class OAuth::PermissiblePolicy < ApplicationRecord
  has_many :rules, class_name: "OAuth::PermissibleRule", foreign_key: "policy_id",
           dependent: :destroy, autosave: true, inverse_of: :policy

  has_many :access_tokens, class_name: "OAuth::AccessToken",
           inverse_of: :permissible_policy, dependent: nil

  has_many :access_grants, class_name: "OAuth::AccessGrant",
           inverse_of: :permissible_policy, dependent: nil

  has_many :device_grants, class_name: "OAuth::DeviceGrant",
           inverse_of: :permissible_policy, dependent: nil

  # Determine if the specified resource can be accessed or not.
  # @param fallback [Boolean, nil] Specify a fallback behavior if an explicit rule was not found.
  def can_access_resource?(resource, fallback: nil)
    denied, allowed = partitioned_rules_for(resource.class.polymorphic_name)
    resource_id = resource.id.to_s

    return false if denied.include?(resource_id)
    return true if allowed.include?(resource_id)
    return fallback unless fallback.nil?

    allowed.empty?
  end

  # Filter an ActiveRecord relation to only records accessible under this policy.
  # Loads all relevant rules in a single query, then applies deny/allow filtering in SQL.
  #
  # @param relation [ActiveRecord::Relation] Relation to filter (model must respond to polymorphic_name)
  # @return [ActiveRecord::Relation] Filtered relation
  def filter_accessible(relation)
    denied, allowed = partitioned_rules_for(relation.model.polymorphic_name)

    relation = relation.where.not(id: denied) if denied.any?
    relation = relation.where(id: allowed) if allowed.any?
    relation
  end

  # Check if implicit denial should be used for this policy. The policy will use implicit denial if *any* rule in the
  # policy is set to explicit allow (deny = false).
  # @param resource_type [String, nil] When set, limit evaluation to this specific type. Used for mixed-resource
  # policies.
  # @return [Boolean] Returns true if implicit-deny mode should be used.
  def implicit_deny?(resource_type: nil)
    search = {deny: false}
    search[:resource_type] = resource_type if resource_type.present?

    rules.where(search).exists?
  end

  private def partitioned_rules_for(resource_type)
    type_rules = rules.where(resource_type:).to_a
    [
      type_rules.select(&:deny).map(&:resource_id).to_set,
      type_rules.reject(&:deny).map(&:resource_id).to_set
    ]
  end
end
