import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="expandable-card"
export default class extends Controller {
  static targets = ["detail", "arrow"]

  toggle() {
    this.detailTarget.classList.toggle("hidden")
    this.arrowTarget.classList.toggle("rotate-180")
  }
}
