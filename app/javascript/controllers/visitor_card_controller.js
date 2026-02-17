import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { stayId: Number }

  checkOut() {
    window.dispatchEvent(new CustomEvent("checkout-visitor", { detail: { stayId: this.stayIdValue } }))
  }
}
