import { Controller } from "@hotwired/stimulus"

// Handles camera capture and photo upload on the camera session page.
//
// Connects to data-controller="camera-session"
export default class extends Controller {
  static targets = ["fileInput", "emptyState", "continueBtn", "readingCount", "bottomBar"]
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

    // Show processing placeholder with thumbnail immediately
    const placeholderId = `processing-${Date.now()}`
    const thumbUrl = URL.createObjectURL(file)
    const container = document.getElementById("detections")
    const position = container.querySelectorAll("[id^='detection-'], [id^='processing-']").length + 1
    const placeholder = document.createElement("div")
    placeholder.id = placeholderId
    placeholder.className = "flex items-start gap-3 p-3 border-2 rounded-xl mb-2 border-blue-200 bg-blue-50"
    placeholder.innerHTML = `
      <div class="w-24 h-24 rounded-lg flex-shrink-0 overflow-hidden">
        <img src="${thumbUrl}" class="w-full h-full object-cover animate-pulse" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 text-sm text-blue-600">
          <span class="inline-block w-3.5 h-3.5 border-2 border-blue-300 border-t-blue-600 rounded-full animate-spin"></span>
          Zpracovávám snímek...
        </div>
        <div class="text-xs font-mono text-blue-300 mt-1">OCR → matching meter</div>
      </div>
    `
    container.appendChild(placeholder)

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

      // Remove placeholder before rendering server response
      document.getElementById(placeholderId)?.remove()
      URL.revokeObjectURL(thumbUrl)

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        // Update button after turbo stream renders
        requestAnimationFrame(() => this.updateContinueButton())
      }
    } catch (error) {
      console.error("Upload failed:", error)
      document.getElementById(placeholderId)?.remove()
      URL.revokeObjectURL(thumbUrl)
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

  // Update the continue button and its label based on usable count
  updateContinueButton() {
    if (!this.hasReadingCountTarget || !this.hasBottomBarTarget) return

    const count = parseInt(this.readingCountTarget.textContent, 10) || 0
    const bar = this.bottomBarTarget

    if (count > 0) {
      // Re-render the bottom bar to show continue button with correct count
      const sessionId = this.sessionIdValue
      const eventType = new URLSearchParams(window.location.search).get("event_type") || "check_in"
      const continueUrl = `/?camera_session_id=${sessionId}&event_type=${eventType}`
      const label = count === 1
        ? `Pokračovat do formuláře (1 odečet) →`
        : `Pokračovat do formuláře (${count} odečty) →`

      bar.innerHTML = `
        <a href="${continueUrl}" class="block w-full text-center py-3.5 rounded-xl bg-white text-blue-600 border-2 border-blue-600 font-medium text-sm hover:bg-blue-50 transition-colors" data-camera-session-target="continueBtn">
          ${label}
        </a>
        <div class="text-center text-xs font-mono text-gray-400 mt-1.5">Před uložením zkontrolujete</div>
        <span class="hidden" id="usable-count" data-camera-session-target="readingCount">${count}</span>
      `
    }
  }
}
