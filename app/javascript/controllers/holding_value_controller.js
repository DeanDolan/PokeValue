import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["condition", "value", "note"]
  static values = { base: Number }

  connect() {
    this.sync()
  }

  // Updates the estimated value preview when the selected condition changes
  sync() {
    if (!this.hasConditionTarget || !this.hasValueTarget) return

    const condition = this.normalize(this.conditionTarget.value)
    const baseValue = Number(this.baseValue || 0)

    if (this.manualConditions().includes(condition)) {
      this.valueTarget.readOnly = false
      this.valueTarget.classList.remove("bg-light")
      this.setNote("This condition is marked as N/A for estimated value.")
      return
    }

    const multiplier = this.reductions()[condition] || 1
    const adjusted = Math.round(baseValue * multiplier * 100) / 100

    this.valueTarget.readOnly = true
    this.valueTarget.classList.add("bg-light")
    this.valueTarget.value = adjusted.toFixed(2)

    if (multiplier === 1) {
      this.setNote("")
    } else {
      this.setNote(`${Math.round((1 - multiplier) * 100)}% condition reduction applied.`)
    }
  }

  // Normalises text so condition names match even if spacing changes
  normalize(value) {
    return String(value || "").trim().toLowerCase().replace(/\s+/g, " ")
  }

  // Conditions where the user should manually enter a value
  manualConditions() {
    return [
      "unsealed",
      "damaged",
      "box only",
      "contents only"
    ]
  }

  // Percentage reductions used for condition-based portfolio values
  reductions() {
    return {
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
  }

  // Writes helper text under the estimated value field
  setNote(text) {
    if (this.hasNoteTarget) this.noteTarget.textContent = text
  }
}