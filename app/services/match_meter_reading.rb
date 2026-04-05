# frozen_string_literal: true

# Uses Gemini LLM to match OCR text to meters and extract reading values.
# Supports multiple readings from a single image (e.g. dual-tariff meters).
#
# Usage:
#   outcome = MatchMeterReading.run(ocr_text: "12345.6 kWh", meters: property.meters.kept)
#   outcome.result # => [{ "meter_id" => 1, "reading_value" => 12345.6, "confidence" => 0.92, "reasoning" => "..." }]
class MatchMeterReading < ApplicationService
  string :ocr_text
  interface :meters, methods: %i[map]

  SCHEMA = {
    type: "object",
    properties: {
      readings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            meter_id:      { type: "integer", description: "ID from meters list, or null if cannot match" },
            reading_value: { type: "number", description: "Numeric value in the meter's unit, or null if unreadable" },
            confidence:    { type: "number", description: "Confidence score 0.0-1.0" },
            reasoning:     { type: "string", description: "Brief explanation of matching logic" }
          },
          required: %w[confidence reasoning]
        },
        description: "One entry per reading found in the image"
      }
    },
    required: %w[readings]
  }.freeze

  MODEL = "gemini-2.0-flash"

  def execute
    prompt_template = File.read(Rails.root.join("app/prompts/match_meter_reading.md"))
    prompt = prompt_template % { ocr_text: ocr_text, meters_json: meters_json }

    chat = RubyLLM.chat(model: MODEL)
    response = chat.with_temperature(0.2).with_schema(SCHEMA).ask(prompt)

    result = parse_response(response)
    return nil unless result

    result["readings"] || [result]
  rescue StandardError => e
    Rails.logger.error("MatchMeterReading failed: #{e.class} - #{e.message}")
    errors.add(:base, "Meter matching failed: #{e.message}")
    nil
  end

  private

  def meters_json
    grouped = meters.group_by(&:identifier)

    grouped.flat_map do |identifier, group_meters|
      group_meters.map do |meter|
        last_reading = meter.last_reading
        entry = {
          id: meter.id,
          label: meter.label,
          meter_type: meter.meter_type,
          meter_group: meter.meter_group,
          unit: meter.unit,
          last_reading_kwh: last_reading&.value_kwh&.to_f
        }
        entry[:identifier] = identifier if identifier.present?
        entry[:same_device_as] = (group_meters - [meter]).map(&:label).join(", ") if identifier.present? && group_meters.size > 1
        entry
      end
    end.to_json
  end

  def parse_response(response)
    content = response.content
    return content if content.is_a?(Hash)

    JSON.parse(content)
  rescue JSON::ParserError => e
    errors.add(:base, "Failed to parse LLM response: #{e.message}")
    nil
  end
end
