import { Controller } from "@hotwired/stimulus"

// Handles camera capture and photo upload on the camera session page.
//
// Connects to data-controller="camera-session"
export default class extends Controller {
  static targets = ["fileInput", "emptyState", "continueBtn", "readingCount"]
  static values = {
    uploadUrl: String,
    reassignUrl: String,
    sessionId: String
  }

  openCamera() {
    this.fileInputTarget.click()
  }

  async photoSelected() {
    const file = this.fileInputTarget.files[0]
    if (!file) return

    // Hide empty state immediately
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.remove()
    }

    const formData = new FormData()
    formData.append("photo", file)

    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken
        },
        body: formData
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error("Upload failed:", error)
    }

    // Reset file input so same file can be re-selected
    this.fileInputTarget.value = ""
  }

  async reassignMeter(event) {
    const select = event.currentTarget
    const detectionId = select.dataset.detectionId
    const meterId = select.value
    if (!meterId) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      await fetch(this.reassignUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken
        },
        body: `detection_id=${detectionId}&meter_id=${meterId}`
      })
      // Visual feedback — update border color to green
      select.classList.remove("border-amber-300", "bg-amber-50")
      select.classList.add("border-emerald-300", "bg-emerald-50")
    } catch (error) {
      console.error("Reassign failed:", error)
    }
  }

  // Called via Stimulus action when turbo stream updates the count
  updateContinueButton() {
    if (this.hasReadingCountTarget && this.hasContinueBtnTarget) {
      const count = parseInt(this.readingCountTarget.textContent, 10) || 0
      const btn = this.continueBtnTarget

      if (count > 0) {
        btn.classList.remove("bg-gray-200", "text-gray-400", "cursor-not-allowed")
        btn.classList.add("bg-white", "text-blue-600", "border-blue-600", "border-2", "font-medium")
        btn.removeAttribute("disabled")
      }
    }
  }
}
