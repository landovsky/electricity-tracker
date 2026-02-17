import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="checkout-form"
export default class extends Controller {
  static targets = ["form", "visitorSelect"]

  connect() {
    // Set initial form action if a visitor is already selected
    this.updateAction()
  }

  updateAction() {
    const selectedOption = this.visitorSelectTarget.selectedOptions[0]
    const stayId = selectedOption?.dataset.stayId

    if (stayId && this.hasFormTarget) {
      // Update form action to the specific stay's check_out path
      this.formTarget.action = `/stays/${stayId}/check_out`
    }
  }
}
