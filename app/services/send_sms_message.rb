# frozen_string_literal: true

# Sends an SMS via SmsManager. Delegates to the appropriate API client.
# Currently uses V1 (HTTP API). Switch to V2 by changing the client below.
class SendSmsMessage < ApplicationService
  string :phone_number
  string :body

  validates :phone_number, presence: true
  validates :body, presence: true

  def execute
    result = client.send_message(phone_number: phone_number, body: body)

    if result[:success]
      result[:message_id]
    else
      Rails.logger.error("SendSmsMessage failed: #{result[:error]}")
      errors.add(:base, "SMS was rejected by the gateway")
      nil
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.error("SendSmsMessage network error: #{e.message}")
    errors.add(:base, "SMS delivery failed: #{e.message}")
    nil
  end

  private

  def client
    @client ||= SmsManager::V1Client.new
  end
end
