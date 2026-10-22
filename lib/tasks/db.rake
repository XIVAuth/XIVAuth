namespace :db do
  task full_reset: %w[db:migrate:reset db:seed]

  desc "Re-encrypt all Active Record encrypted attributes under the current (last) primary key"
  task reencrypt: :environment do
    Rails.application.eager_load!

    # Iterate STI hierarchies from their base class so every row in the table is covered, whichever subclass declares
    # the encrypted attributes. Framework models (e.g. Action Text) may be loaded without their tables existing.
    models = ActiveRecord::Base.descendants
                               .reject(&:abstract_class?)
                               .select { |model| model.encrypted_attributes.present? }
                               .map(&:base_class)
                               .uniq
                               .select(&:table_exists?)

    # Rails encrypts with the last primary key and decrypts with any of them. Verifying against only the last key proves
    # nothing still depends on a previous one.
    current_key_provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new(
      Array(ActiveRecord::Encryption.config.primary_key).last
    )
    encryptor = ActiveRecord::Encryption::Encryptor.new
    failures = 0

    models.each do |model|
      count = 0

      model.find_each do |record|
        record.encrypt

        record.class.encrypted_attributes.each do |attribute|
          ciphertext = record.ciphertext_for(attribute)
          encryptor.decrypt(ciphertext, key_provider: current_key_provider) if ciphertext.present?
        end

        count += 1
      rescue ActiveRecord::Encryption::Errors::Base => e
        failures += 1
        warn "  #{model.name} #{record.id}: #{e.class}: #{e.message}"
      end

      puts "#{model.name}: re-encrypted #{count} record(s)"
    end

    abort "#{failures} record(s) failed to re-encrypt. Do not remove previous keys." if failures.positive?

    puts "All encrypted values decrypt with the current primary key. Previous primary keys can be removed."
  end
end
