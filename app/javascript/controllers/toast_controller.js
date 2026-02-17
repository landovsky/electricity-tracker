import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toast"
export default class extends Controller {
  static values = {
    duration: { type: Number, default: 3000 }
  }

  connect() {
    // Fade in
    requestAnimationFrame(() => {
      this.element.style.opacity = "1"
    })

    // Auto-dismiss after duration
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, this.durationValue)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    // Fade out
    this.element.style.opacity = "0"

    // Remove from DOM after transition
    setTimeout(() => {
      this.element.remove()
    }, 300) // Match transition duration in CSS
  }
}
