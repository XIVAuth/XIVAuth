class OAuth::CleanupStaleRecordsJob < ApplicationJob
  queue_as :cronjobs

  def perform(*)
    clean_access_grants
    clean_device_grants
    clean_access_tokens
    clean_permissible_policies
  end

  def clean_access_grants(cutoff = 24.hours.ago)
    OAuth::AccessGrant.where(revoked_at: ..cutoff)
                      .tap { |rel| logger.info("Scheduling #{rel.count} revoked AccessGrants for deletion.") }
                      .in_batches(&:delete_all)

    OAuth::AccessGrant.where.not(expires_in: nil)
                      .where("(created_at + expires_in * INTERVAL '1 second') < ?", cutoff)
                      .tap { |rel| logger.info("Scheduling #{rel.count} expired AccessGrants for deletion.") }
                      .in_batches(&:delete_all)
  end

  def clean_device_grants(cutoff = 24.hours.ago)
    OAuth::DeviceGrant.where.not(expires_in: nil)
                      .where("(created_at + expires_in * INTERVAL '1 second') < ?", cutoff)
                      .tap { |rel| logger.info("Scheduling #{rel.count} expired DeviceGrants for deletion.") }
                      .in_batches(&:delete_all)
  end

  def clean_access_tokens(cutoff = 7.days.ago)
    OAuth::AccessToken.where(revoked_at: ..cutoff)
                      .tap { |rel| logger.info("Scheduling #{rel.count} revoked AccessTokens for deletion.") }
                      .in_batches(&:delete_all)

    OAuth::AccessToken.where(refresh_token: nil)
                      .where.not(expires_in: nil)
                      .where("(created_at + expires_in * INTERVAL '1 second') < ?", cutoff)
                      .tap { |rel| logger.info("Scheduling #{rel.count} expired AccessTokens for deletion.") }
                      .in_batches(&:delete_all)
  end

  def clean_permissible_policies
    orphaned = OAuth::PermissiblePolicy.left_outer_joins(:access_tokens, :access_grants, :device_grants)
                                       .where(oauth_access_tokens: { id: nil }, oauth_access_grants: { id: nil },
                                              oauth_device_grants: { id: nil })

    logger.info("Scheduling #{orphaned.count} orphaned PermissiblePolicies for deletion.")

    orphaned.in_batches do |batch|
      # delete rules first, since we use delete_all and a FK is present.
      OAuth::PermissibleRule.where(policy_id: batch).delete_all
      batch.delete_all
    end
  end
end
