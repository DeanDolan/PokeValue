import "@hotwired/turbo-rails"
import "controllers"

// Runs setup code after both normal page loads and Turbo page changes.
const onPageReady = (callback) => {
  document.addEventListener("DOMContentLoaded", callback)
  document.addEventListener("turbo:load", callback)
}

// Prevents the login/register modal from closing when the user clicks outside it or presses Escape.
const setupStaticAuthModal = () => {
  const modal = document.getElementById("authModal")

  if (!modal) return

  modal.setAttribute("data-bs-backdrop", "static")
  modal.setAttribute("data-bs-keyboard", "false")

  if (!window.bootstrap || !window.bootstrap.Modal) return
  if (modal.dataset.staticAuthReady === "1") return

  modal.dataset.staticAuthReady = "1"

  const existingInstance = window.bootstrap.Modal.getInstance(modal)

  if (existingInstance && !modal.classList.contains("show")) {
    existingInstance.dispose()
  }

  if (!modal.classList.contains("show")) {
    window.bootstrap.Modal.getOrCreateInstance(modal, {
      backdrop: "static",
      keyboard: false
    })
  }
}

// Lets the country dropdown jump to a country when the user types letters.
const setupCountrySelectTyping = () => {
  document.querySelectorAll("[data-country-search='true']").forEach((select) => {
    if (select.dataset.typingSearchReady === "1") return

    select.dataset.typingSearchReady = "1"

    const options = Array.from(select.options).filter((option) => option.value !== "")
    let typed = ""
    let timer = null

    // Removes the flag emoji from the start so searches match the country name.
    const cleanCountryText = (text) => {
      return text.toLowerCase().replace(/^[^\p{L}\p{N}]+/u, "").trim()
    }

    // Stores typed letters for one second and selects the best matching country.
    select.addEventListener("keydown", (event) => {
      const key = event.key

      if (key === "Backspace") {
        typed = typed.slice(0, -1)
      } else if (key === "Escape") {
        typed = ""
        return
      } else if (key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
        typed += key.toLowerCase()
      } else {
        return
      }

      clearTimeout(timer)

      timer = setTimeout(() => {
        typed = ""
      }, 1000)

      const match = options.find((option) => cleanCountryText(option.text).startsWith(typed)) ||
        options.find((option) => cleanCountryText(option.text).includes(typed))

      if (match) {
        select.value = match.value
        select.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
  })
}

// Starts all shared JavaScript.
onPageReady(() => {
  setupStaticAuthModal()
  setupCountrySelectTyping()
})