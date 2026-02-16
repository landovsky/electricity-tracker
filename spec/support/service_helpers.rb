# frozen_string_literal: true

# Shared helpers and configuration for service object specs.
#
# Service specs test business logic in isolation. They should:
# - Test the happy path
# - Test validation failures
# - Test edge cases and error conditions
# - Use real database records (via FactoryBot) for integration
# - Mock external dependencies (APIs, third-party services)
#
# Example:
#   RSpec.describe MyService, type: :service do
#     describe ".run" do
#       context "with valid inputs" do
#         it "performs the operation successfully" do
#           outcome = described_class.run(name: "Alice")
#           expect(outcome).to be_valid
#           expect(outcome.result).to eq(expected_value)
#         end
#       end
#
#       context "with invalid inputs" do
#         it "returns validation errors" do
#           outcome = described_class.run(name: nil)
#           expect(outcome).to be_invalid
#           expect(outcome.errors[:name]).to include("is required")
#         end
#       end
#     end
#   end

RSpec.configure do |config|
  # Infer service type from file location
  config.define_derived_metadata(file_path: %r{/spec/services/}) do |metadata|
    metadata[:type] = :service
  end
end
