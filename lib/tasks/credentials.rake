namespace :credentials do
  desc "Re-encrypt a credentials file under a newly generated key (ENVIRONMENT=production, OLD_KEY=... if no key file)"
  task :rotate, [:environment] do |_t, args|
    require "active_support/encrypted_configuration"

    env = args[:environment].presence || ENV["ENVIRONMENT"].presence
    if env
      content_path = Rails.root.join("config/credentials/#{env}.yml.enc")
      key_path     = Rails.root.join("config/credentials/#{env}.key")
    else
      content_path = Rails.root.join("config/credentials.yml.enc")
      key_path     = Rails.root.join("config/master.key")
    end

    abort "No credentials file at #{content_path}" unless content_path.exist?

    old_config = ActiveSupport::EncryptedConfiguration.new(
      config_path: content_path, key_path: key_path, env_key: "OLD_KEY", raise_if_missing_key: true
    )

    plaintext = begin
      old_config.read
    rescue ActiveSupport::EncryptedFile::MissingKeyError
      abort "No key found for #{content_path}. Pass the current key as OLD_KEY=..."
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      abort "The current key does not decrypt #{content_path}."
    end

    # Backups go under tmp/ so the old key can't be committed by accident.
    backup_dir = Rails.root.join("tmp/credentials-rotate/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}")
    FileUtils.mkdir_p(backup_dir, mode: 0o700)
    FileUtils.cp(content_path, backup_dir)
    File.write(backup_dir.join(key_path.basename), old_config.key, perm: 0o600)

    new_key = ActiveSupport::EncryptedFile.generate_key
    File.write(key_path, new_key, perm: 0o600)

    new_config = ActiveSupport::EncryptedConfiguration.new(
      config_path: content_path, key_path: key_path, env_key: "UNUSED_CREDENTIALS_ROTATE_KEY",
      raise_if_missing_key: true
    )
    new_config.write(plaintext)

    abort "Verification failed! Restore from #{backup_dir}." unless new_config.read == plaintext

    puts "Rotated #{content_path.relative_path_from(Rails.root)}"
    puts "  new key written to: #{key_path.relative_path_from(Rails.root)}"
    puts "  old file + key backed up to: #{backup_dir.relative_path_from(Rails.root)}"
    puts
    puts "Update RAILS_MASTER_KEY wherever this file is deployed, then commit the new .yml.enc."
  end
end
