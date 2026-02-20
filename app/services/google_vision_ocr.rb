# frozen_string_literal: true

# Extracts text from an image using Google Cloud Vision API (TEXT_DETECTION).
#
# Direct REST call via Net::HTTP — no heavy gem dependency.
#
# Usage:
#   outcome = GoogleVisionOcr.run(image_data: blob.download)
#   outcome.result # => { text: "...", full_response: { ... } }
class GoogleVisionOcr < ApplicationService
  string :image_data

  validate :validate_api_key_present

  def execute
    response = call_vision_api
    body = JSON.parse(response.body)

    if response.code != "200"
      error_msg = body.dig("error", "message") || "Vision API returned #{response.code}"
      errors.add(:base, error_msg)
      return nil
    end

    annotations = body.dig("responses", 0, "textAnnotations") || []
    text = annotations.first&.dig("description") || ""

    { text: text, full_response: body }
  end

  private

  def validate_api_key_present
    errors.add(:base, "GOOGLE_CLOUD_API_KEY is not set") if api_key.blank?
  end

  def api_key
    ENV["GOOGLE_CLOUD_API_KEY"]
  end

  def call_vision_api
    uri = URI("https://vision.googleapis.com/v1/images:annotate?key=#{api_key}")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = request_body.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
  end

  def request_body
    {
      requests: [
        {
          image: { content: Base64.strict_encode64(image_data) },
          features: [ { type: "TEXT_DETECTION" } ]
        }
      ]
    }
  end
end
