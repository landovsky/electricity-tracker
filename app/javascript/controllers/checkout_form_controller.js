import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="checkout-form"
export default class extends Controller {
  static targets = ["form", "visitorSelect"]
  static values = { pathTemplate: String }

  connect() {
    // Set initial form action if a visitor is already selected
    this.updateAction()
  }

  updateAction() {
    const selectedOption = this.visitorSelectTarget.selectedOptions[0]
    const stayId = selectedOption?.dataset.stayId

    if (stayId && this.hasFormTarget && this.hasPathTemplateValue) {
      this.formTarget.action = this.pathTemplateValue.replace("__STAY_ID__", stayId)
    }
  }
}
