# frozen_string_literal: true

RubyLLM.configure do |config|
  config.gemini_api_key = ENV["GEMINI_API_KEY"]
  config.use_new_acts_as = true
end
