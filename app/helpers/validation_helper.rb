# frozen_string_literal: true

module ValidationHelper
  def generic_field_validation(text = nil, required: true)
    text ||= t("form.validation.error.required")
    {
      oninvalid: "this.setCustomValidity('#{text}')",
      onvalid: 'this.setCustomValidity("")',
      oninput: 'this.setCustomValidity("")',
      required:
    }
  end

  def field_validation(required: true)
    generic_field_validation t("form.validation.error.field"), required:
  end

  def select_validation(required: true)
    generic_field_validation t("form.validation.error.select"), required:
  end

  def number_validation(required: true)
    generic_field_validation t("form.validation.error.number"), required:
  end

  def email_validation(required: true)
    generic_field_validation t("form.validation.error.email"), required:
  end
end
