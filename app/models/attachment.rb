class Attachment < ApplicationRecord
  include AttachmentUploader::Attachment(:file)

  belongs_to :record, polymorphic: true

  after_commit :enqueue_derivatives, if: :promoted_to_store?

  # Returns the URL for the given derivative, falling back to the original
  # if the derivative has not been generated yet.
  def url(derivative: nil, **options)
    if derivative
      (file_attacher.derivatives[derivative] || file)&.url(**options)
    else
      file&.url(**options)
    end
  end

  def owner_attachment_config
    owner_class = record_type&.safe_constantize
    owner_class&.upload_attachment_configs&.dig(name&.to_sym) || {}
  end

  private

  def promoted_to_store?
    file_data_previously_changed? && file&.storage_key == :store
  end

  def enqueue_derivatives
    Attachment::GenerateDerivativesJob.perform_later(id, file_attacher.data)
  end
end
