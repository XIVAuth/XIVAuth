RSpec.describe User::Profile, type: :model do
  describe "#implicit_order_column" do
    it "does not have an implicit order column" do
      expect(subject.class.implicit_order_column).to be_nil
    end
  end
end