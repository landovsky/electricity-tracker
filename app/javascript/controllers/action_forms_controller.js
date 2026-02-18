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

    this.handleCheckoutVisitor = this.checkOutVisitor.bind(this)
    window.addEventListener("checkout-visitor", this.handleCheckoutVisitor)
  }

  disconnect() {
    window.removeEventListener("checkout-visitor", this.handleCheckoutVisitor)
  }

  checkOutVisitor(event) {
    const stayId = event.detail.stayId
    this.switchToTab("checkout")

    const select = this.element.querySelector('[name="stay_id"]')
    if (select) {
      select.value = stayId
      select.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  switchTab(event) {
    // Handle both click events and direct calls
    const tabName = event.currentTarget ? event.currentTarget.dataset.tab : event
    this.switchToTab(tabName)
  }

  // Color mapping: data-active-color → [border, text, active bg]
  static colorMap = {
    emerald: ["border-emerald-600", "text-emerald-700", "bg-emerald-50"],
    amber:   ["border-amber-600",   "text-amber-700",   "bg-amber-50"],
    violet:  ["border-violet-600",  "text-violet-700",  "bg-violet-50"],
  }

  switchToTab(tabName) {
    // Update all tab buttons
    this.tabButtonTargets.forEach(button => {
      const isActive = button.dataset.tab === tabName
      const color = button.dataset.activeColor || "brand"
      const [borderClass, textClass, bgClass] = this.constructor.colorMap[color] || ["border-brand-600", "text-brand-700", "bg-brand-50"]

      // Remove all possible bg/border classes
      const allBg = Object.values(this.constructor.colorMap).map(c => c[2])
      const allBorder = Object.values(this.constructor.colorMap).map(c => c[0])
      button.classList.remove(...allBg, ...allBorder, "border-transparent")

      // Text color is always the tab's own color
      button.classList.remove("text-gray-500", "hover:text-gray-700", "hover:border-gray-300")
      button.classList.add(textClass)

      if (isActive) {
        button.classList.add(borderClass, bgClass)
      } else {
        button.classList.add("border-transparent")
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
