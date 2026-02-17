# frozen_string_literal: true

require "net/http"
require "json"

module SmsManager
  # SmsManager JSON API v2 client.
  # Docs: https://api-ref.smsmanager.com/openapi/cs/json/jsonapi_v2
  #
  # Endpoint: POST https://api.smsmngr.com/v2/message
  # Auth: x-api-key header
  # Response: { "request_id": "...", "accepted": [...], "rejected": [...] }
  class V2Client
    API_URL = "https://api.smsmngr.com/v2/message"

    def initialize(api_key: nil)
      @api_key = api_key || ENV["SMS_MANAGER_API_KEY_V2"] || Rails.application.credentials.sms_manager_api_key_v2
      raise "Missing SMS_MANAGER_API_KEY_V2" unless @api_key
    end

    # Sends an SMS and returns { success: true, message_id: "..." }
    # or { success: false, error: "..." }
    def send_message(phone_number:, body:)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["x-api-key"] = @api_key
      request["Content-Type"] = "application/json"
      request.body = { body: body, to: [{ phone_number: phone_number }] }.to_json

      response = http.request(request)
      parse_response(response)
    end

    private

    def parse_response(response)
      payload = JSON.parse(response.body)
      if response.is_a?(Net::HTTPSuccess) && payload["accepted"]&.any?
        { success: true, message_id: payload["accepted"].first["message_id"] }
      else
        { success: false, error: payload.to_json }
      end
    end
  end
end
