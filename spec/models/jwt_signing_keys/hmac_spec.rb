require "rails_helper"

RSpec.describe JwtSigningKeys::HMAC do
  subject { described_class.new(name: "rspec_hmac_#{SecureRandom.uuid}") }

  it "is not valid without a name" do
    subject.name = nil
    expect(subject).not_to be_valid
  end

  it "contains a private key at initialization" do
    expect(subject.private_key).not_to be_nil
    expect(subject.public_key).to be_nil
  end

  it "correctly persists the key" do
    subject.save

    ci = described_class.find_by(name: subject.name)
    expect(ci.raw_private_key).to eq(subject.raw_private_key)
  end

  it "doesn't allow setting size" do
    old_size = subject.size
    subject.size = 512

    expect(subject.size).to eq(old_size)
  end

  it "allows setting size on creation" do
    hm_key = described_class.new(name: "size test", size: 64)
    expect(hm_key.size).to eq(64)
  end

  it "reports supported algorithms" do
    expect(subject.supported_algorithms).to contain_exactly("HS256", "HS384", "HS512")
  end
end
