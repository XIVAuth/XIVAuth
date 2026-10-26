require "rails_helper"
require "rake"

RSpec.describe "db:encryption:rotate" do # rubocop:disable RSpec/DescribeClass
  let(:old_keys) { ActiveRecord::Encryption::DerivedSecretKeyProvider.new("old-primary-key") }
  let(:rotated_keys) { ActiveRecord::Encryption::DerivedSecretKeyProvider.new(%w[old-primary-key new-primary-key]) }
  let(:new_keys) { ActiveRecord::Encryption::DerivedSecretKeyProvider.new("new-primary-key") }
  let(:encryptor) { ActiveRecord::Encryption::Encryptor.new }

  before { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "db:encryption:rotate" } }

  after { Rake::Task["db:encryption:rotate"].reenable }

  it "re-encrypts values so they decrypt with only the new primary key" do
    key = ActiveRecord::Encryption.with_encryption_context(encryptor: encryptor, key_provider: old_keys) do
      FactoryBot.create(:jwt_signing_keys_ed25519)
    end
    plaintext = encryptor.decrypt(key.ciphertext_for(:private_key), key_provider: old_keys)

    expect { encryptor.decrypt(key.ciphertext_for(:private_key), key_provider: new_keys) }
      .to raise_error(ActiveRecord::Encryption::Errors::Decryption)

    allow(ActiveRecord::Encryption.config).to receive(:primary_key).and_return(%w[old-primary-key new-primary-key])
    ActiveRecord::Encryption.with_encryption_context(encryptor: encryptor, key_provider: rotated_keys) do
      expect { Rake::Task["db:encryption:rotate"].invoke }.to output(/JwtSigningKey: re-encrypted 1 record/).to_stdout
    end

    expect(encryptor.decrypt(key.reload.ciphertext_for(:private_key), key_provider: new_keys)).to eq(plaintext)
  end
end
