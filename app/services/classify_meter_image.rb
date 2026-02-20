# frozen_string_literal: true

# Uses Gemini LLM to determine if OCR text comes from a utility meter photo
# (electricity, gas, or water).
#
# Usage:
#   outcome = ClassifyMeterImage.run(ocr_text: "12345.6 kWh NT")
#   outcome.result # => { "is_meter" => true, "confidence" => 0.95, "explanation" => nil }
class ClassifyMeterImage < ApplicationService
  string :ocr_text

  SCHEMA = {
    type: "object",
    properties: {
      is_meter:    { type: "boolean", description: "Whether the OCR text is from a utility meter (electricity, gas, or water)" },
      confidence:  { type: "number", description: "Confidence score 0.0-1.0" },
      explanation: { type: "string", description: "Brief reason if not a meter, or null" }
    },
    required: %w[is_meter confidence]
  }.freeze

  MODEL = "gemini-2.0-flash"

  def execute
    prompt_template = File.read(Rails.root.join("app/prompts/classify_meter_image.md"))
    prompt = prompt_template % { ocr_text: ocr_text }

    chat = RubyLLM.chat(model: MODEL)
    response = chat.with_temperature(0.2).with_schema(SCHEMA).ask(prompt)

    parse_response(response)
  rescue StandardError => e
    Rails.logger.error("ClassifyMeterImage failed: #{e.class} - #{e.message}")
    errors.add(:base, "Classification failed: #{e.message}")
    nil
  end

  private

  def parse_response(response)
    content = response.content
    return content if content.is_a?(Hash)

    JSON.parse(content)
  rescue JSON::ParserError => e
    errors.add(:base, "Failed to parse LLM response: #{e.message}")
    nil
  end
end
