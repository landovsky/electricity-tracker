# frozen_string_literal: true

require "net/http"
require "uri"

module SmsManager
  # SmsManager HTTP API v1 client.
  # Docs: https://smsmanager.cz/docs/api/v1/http-api/send/
  #
  # Endpoint: GET https://http-api.smsmanager.cz/Send
  # Auth: apikey query parameter
  # Response: "OK|<message_id>|<number>" or "ERROR|<code>"
  class V1Client
    API_URL = "https://http-api.smsmanager.cz/Send"

    def initialize(api_key: nil)
      @api_key = api_key || ENV["SMS_MANAGER_API_KEY"] || Rails.application.credentials.sms_manager_api_key
      raise "Missing SMS_MANAGER_API_KEY" unless @api_key
    end

    # Sends an SMS and returns { success: true, message_id: "..." }
    # or { success: false, error: "..." }
    def send_message(phone_number:, body:)
      # Strip leading + for the API (expects 420... not +420...)
      number = phone_number.delete("+")

      uri = URI(API_URL)
      uri.query = URI.encode_www_form(
        apikey: @api_key,
        message: body,
        number: number,
        type: "utf"
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 10

      response = http.request(Net::HTTP::Get.new(uri))
      parse_response(response.body.strip)
    end

    private

    def parse_response(body)
      parts = body.split("|")
      if parts[0] == "OK"
        { success: true, message_id: parts[1], number: parts[2] }
      else
        { success: false, error: body }
      end
    end
  end
end
