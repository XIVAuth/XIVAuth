class Attachment::GenerateDerivativesJob < ApplicationJob
  queue_as :default

  def perform(attachment_id, file_data)
    attachment = Attachment.find(attachment_id)
    attacher = AttachmentUploader::Attacher.retrieve(model: attachment, name: "file", file: file_data)
    return if attacher.derivatives.any?

    attacher.create_derivatives
    attacher.atomic_persist
  rescue Shrine::AttachmentChanged, ActiveRecord::RecordNotFound
    # File was replaced or the record was deleted before the job ran — discard.
  end
end
