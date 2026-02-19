import { Controller } from "@hotwired/stimulus"

// Hint popover: hover on desktop, tap on mobile. Only one open at a time.
export default class extends Controller {
  static targets = ["bubble"]

  show() {
    this.constructor._closeAll(this)
    this.bubbleTarget.classList.remove("hidden")
  }

  hide() {
    this.bubbleTarget.classList.add("hidden")
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const wasHidden = this.bubbleTarget.classList.contains("hidden")
    this.constructor._closeAll()
    if (wasHidden) {
      this.bubbleTarget.classList.remove("hidden")
    }
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  connect() {
    this._close = this.close.bind(this)
    document.addEventListener("click", this._close)
    this.constructor._instances.add(this)
  }

  disconnect() {
    document.removeEventListener("click", this._close)
    this.constructor._instances.delete(this)
  }

  static _instances = new Set()

  static _closeAll(except = null) {
    this._instances.forEach((instance) => {
      if (instance !== except) instance.hide()
    })
  }
}
