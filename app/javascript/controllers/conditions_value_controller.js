import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Connects the HTML condition, value and note fields to this controller.
  static targets = ["condition", "value", "note"]

  // Stores the original base product value sent from the page.
  static values = { base: Number }

  // Runs when the condition value controller loads.
  connect() {
    this.sync()
  }

  // Updates the estimated value field when the selected condition changes.
  sync() {
    if (!this.hasConditionTarget || !this.hasValueTarget) return

    const condition = String(this.conditionTarget.value || "").trim().toLowerCase().replace(/\s+/g, " ")
    const baseValue = Number(this.baseValue || 0)

    const manualConditions = [
      "unsealed",
      "damaged",
      "box only",
      "contents only"
    ]

    const reductions = {
      "loosely sealed": 0.9,
      "mini tear/hole (<2cm)": 0.9,
      "mini tear/hole (1cm)": 0.9,
      "pressure marks": 0.9,
      "small imperfections": 0.9,
      "big imperfections": 0.85,
      "small tear": 0.85,
      "small tear (>2cm)": 0.85,
      "small tear (<1 inch)": 0.85,
      "big tear": 0.8,
      "big tear (>1 inch)": 0.8,
      "big tear (>inch)": 0.8,
      "slightly dented": 0.8,
      "heavy dented": 0.7
    }

    if (manualConditions.includes(condition)) {
      this.valueTarget.readOnly = false
      this.valueTarget.classList.remove("bg-light")

      if (this.hasNoteTarget) {
        this.noteTarget.textContent = "This condition is marked as N/A for estimated value."
      }

      return
    }

    const multiplier = reductions[condition] || 1
    const adjusted = Math.round(baseValue * multiplier * 100) / 100

    this.valueTarget.readOnly = true
    this.valueTarget.classList.add("bg-light")
    this.valueTarget.value = adjusted.toFixed(2)

    if (this.hasNoteTarget) {
      this.noteTarget.textContent = multiplier === 1 ? "" : `${Math.round((1 - multiplier) * 100)}% condition reduction applied.`
    }
  }
}