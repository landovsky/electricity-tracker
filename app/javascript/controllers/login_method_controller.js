import { Controller } from "@hotwired/stimulus"

// Toggles between email/SMS login forms and the about panel on the login screen.
export default class extends Controller {
  static targets = [
    "emailButton", "smsButton", "emailPanel", "smsPanel",
    "loginTab", "aboutTab", "loginPanel", "aboutPanel"
  ]

  showLogin() {
    this.activateTab(this.loginTabTarget)
    this.deactivateTab(this.aboutTabTarget)
    this.showPanel(this.loginPanelTarget)
    this.hidePanel(this.aboutPanelTarget)
  }

  showAbout() {
    this.activateTab(this.aboutTabTarget)
    this.deactivateTab(this.loginTabTarget)
    this.showPanel(this.aboutPanelTarget)
    this.hidePanel(this.loginPanelTarget)
  }

  showPanel(panel) {
    panel.classList.remove("opacity-0", "pointer-events-none")
    panel.classList.add("opacity-100")
  }

  hidePanel(panel) {
    panel.classList.add("opacity-0", "pointer-events-none")
    panel.classList.remove("opacity-100")
  }

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

  activateTab(tab) {
    tab.classList.remove("border-transparent", "text-gray-400", "hover:text-gray-600")
    tab.classList.add("border-brand-600", "text-brand-700")
  }

  deactivateTab(tab) {
    tab.classList.remove("border-brand-600", "text-brand-700")
    tab.classList.add("border-transparent", "text-gray-400", "hover:text-gray-600")
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
