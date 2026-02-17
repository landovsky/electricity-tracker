import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="action-forms"
export default class extends Controller {
  static targets = ["tabButton", "formPanel"]
  static values = {
    defaultTab: String
  }

  connect() {
    // Set initial active tab based on default
    const defaultTab = this.defaultTabValue || "checkin"
    this.switchToTab(defaultTab)
  }

  switchTab(event) {
    // Handle both click events and direct calls
    const tabName = event.currentTarget ? event.currentTarget.dataset.tab : event
    this.switchToTab(tabName)
  }

  switchToTab(tabName) {
    // Update all tab buttons
    this.tabButtonTargets.forEach(button => {
      const isActive = button.dataset.tab === tabName

      if (isActive) {
        // Active tab styling
        button.classList.remove("border-transparent", "text-gray-500", "hover:text-gray-700", "hover:border-gray-300")
        button.classList.add("border-brand-600", "text-brand-600")
      } else {
        // Inactive tab styling
        button.classList.remove("border-brand-600", "text-brand-600")
        button.classList.add("border-transparent", "text-gray-500", "hover:text-gray-700", "hover:border-gray-300")
      }
    })

    // Show/hide form panels
    this.formPanelTargets.forEach(panel => {
      const panelType = panel.dataset.formType
      if (panelType === tabName) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}
