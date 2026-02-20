# frozen_string_literal: true

# Extracts text from an image using Google Cloud Vision API (TEXT_DETECTION).
#
# Uses GOOGLE_APPLICATION_CREDENTIALS_JSON (inline JSON) or
# GOOGLE_APPLICATION_CREDENTIALS (file path) service account for auth.
#
# Usage:
#   outcome = GoogleVisionOcr.run(image_data: blob.download)
#   outcome.result # => { text: "...", full_response: { ... } }
class GoogleVisionOcr < ApplicationService
  string :image_data

  SCOPE = "https://www.googleapis.com/auth/cloud-vision"

  validate :validate_credentials_present

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

  def validate_credentials_present
    if ENV["GOOGLE_APPLICATION_CREDENTIALS_JSON"].blank? && ENV["GOOGLE_APPLICATION_CREDENTIALS"].blank?
      errors.add(:base, "GOOGLE_APPLICATION_CREDENTIALS_JSON or GOOGLE_APPLICATION_CREDENTIALS must be set")
    end
  end

  def access_token
    json_key_io = if ENV["GOOGLE_APPLICATION_CREDENTIALS_JSON"].present?
      StringIO.new(ENV["GOOGLE_APPLICATION_CREDENTIALS_JSON"])
    else
      File.open(ENV["GOOGLE_APPLICATION_CREDENTIALS"])
    end
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: json_key_io, scope: SCOPE)
    authorizer.fetch_access_token!["access_token"]
  end

  def call_vision_api
    uri = URI("https://vision.googleapis.com/v1/images:annotate")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{access_token}"
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
