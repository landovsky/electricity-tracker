import { Controller } from "@hotwired/stimulus"

// Toggles between email and SMS login forms on the login screen.
// Connects to data-controller="login-method"
export default class extends Controller {
  static targets = ["emailButton", "smsButton", "emailPanel", "smsPanel"]

  selectEmail() {
    this.activateButton(this.emailButtonTarget)
    this.deactivateButton(this.smsButtonTarget)
    this.emailPanelTarget.classList.remove("hidden")
    this.smsPanelTarget.classList.add("hidden")
  }

  selectSms() {
    this.activateButton(this.smsButtonTarget)
    this.deactivateButton(this.emailButtonTarget)
    this.smsPanelTarget.classList.remove("hidden")
    this.emailPanelTarget.classList.add("hidden")
  }

  activateButton(button) {
    button.classList.remove("border-gray-200", "text-gray-500", "hover:border-gray-300")
    button.classList.add("border-brand-600", "bg-brand-50", "text-brand-700")
  }

  deactivateButton(button) {
    button.classList.remove("border-brand-600", "bg-brand-50", "text-brand-700")
    button.classList.add("border-gray-200", "text-gray-500", "hover:border-gray-300")
  }
}
