import { Controller } from "@hotwired/stimulus"

// Handles camera capture and photo upload on the camera session page.
//
// Connects to data-controller="camera-session"
export default class extends Controller {
  static targets = ["fileInput", "emptyState", "continueBtn", "readingCount", "bottomBar"]
  static values = {
    uploadUrl: String,
    reassignUrl: String,
    sessionId: String,
    eventType: String,
    uploadErrorMessage: String,
    reassignErrorMessage: String
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
      } else {
        // 422 responses carry a user-facing reason as plain text
        const reason = response.status === 422 ? (await response.text()).trim() : ""
        this.showUploadError(container, reason || this.uploadErrorMessageValue)
      }
    } catch (error) {
      console.error("Upload failed:", error)
      document.getElementById(placeholderId)?.remove()
      URL.revokeObjectURL(thumbUrl)
      this.showUploadError(container, this.uploadErrorMessageValue)
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
    const body = new URLSearchParams({ detection_id: detectionId, meter_id: meterId })

    let response = null
    try {
      response = await fetch(this.reassignUrlValue, {
        method: "PATCH",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken
        },
        body
      })
    } catch (error) {
      console.error("Reassign failed:", error)
    }

    if (response?.ok) {
      // Server re-renders the card (and any card it replaced) with the saved state
      Turbo.renderStreamMessage(await response.text())
      requestAnimationFrame(() => this.updateContinueButton())
    } else {
      // Not saved — restore the previous choice so the UI never claims a save that didn't happen
      // (data-saved-meter-id is rendered by the server with the persisted meter)
      select.value = select.dataset.savedMeterId ?? ""
      select.classList.remove("border-emerald-300", "bg-emerald-50")
      select.classList.add("border-red-300", "bg-red-50")
      window.alert(this.reassignErrorMessageValue)
    }
  }

  showUploadError(container, message) {
    const card = document.createElement("div")
    card.className = "flex items-start gap-3 p-3 border-2 rounded-xl mb-2 border-red-200 bg-red-50 text-sm text-red-600"
    card.setAttribute("role", "alert")
    card.textContent = message
    container.appendChild(card)
  }

  // Update the continue button and its label based on usable count
  updateContinueButton() {
    if (!this.hasReadingCountTarget || !this.hasBottomBarTarget) return

    const count = parseInt(this.readingCountTarget.textContent, 10) || 0
    const bar = this.bottomBarTarget

    if (count > 0) {
      // Built with DOM APIs, never innerHTML: session id and event type come from the URL
      const url = new URL("/", window.location.origin)
      url.searchParams.set("camera_session_id", this.sessionIdValue)
      url.searchParams.set("event_type", this.eventTypeValue === "check_out" ? "check_out" : "check_in")

      const link = document.createElement("a")
      link.href = url.pathname + url.search
      link.className = "block w-full text-center py-3.5 rounded-xl bg-white text-blue-600 border-2 border-blue-600 font-medium text-sm hover:bg-blue-50 transition-colors"
      link.dataset.cameraSessionTarget = "continueBtn"
      link.textContent = count === 1
        ? "Pokračovat do formuláře (1 odečet) →"
        : `Pokračovat do formuláře (${count} odečty) →`

      const hint = document.createElement("div")
      hint.className = "text-center text-xs font-mono text-gray-400 mt-1.5"
      hint.textContent = "Před uložením zkontrolujete"

      const counter = document.createElement("span")
      counter.className = "hidden"
      counter.id = "usable-count"
      counter.dataset.cameraSessionTarget = "readingCount"
      counter.textContent = String(count)

      bar.replaceChildren(link, hint, counter)
    }
  }
}
