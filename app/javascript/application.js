import "@hotwired/turbo-rails"
import "controllers"

// Runs JavaScript safely after normal page loads and Turbo page changes
const onPageReady = (callback) => {
  document.addEventListener("DOMContentLoaded", callback)
  document.addEventListener("turbo:load", callback)
}

// Makes the register country dropdown searchable while keeping it as a dropdown-style field
const setupRegisterCountryDropdown = () => {
  document.querySelectorAll("[data-country-dropdown]").forEach((dropdown) => {
    if (dropdown.dataset.countryReady === "true") return
    dropdown.dataset.countryReady = "true"

    const toggle = dropdown.querySelector("[data-country-toggle]")
    const selected = dropdown.querySelector("[data-country-selected]")
    const menu = dropdown.querySelector("[data-country-menu]")
    const search = dropdown.querySelector("[data-country-search]")
    const hidden = dropdown.querySelector("[data-country-hidden]")
    const optionsWrap = dropdown.querySelector("[data-country-options]")
    const options = Array.from(dropdown.querySelectorAll("[data-country-option]"))

    if (!toggle || !selected || !menu || !search || !hidden || !optionsWrap) return

    const closeMenu = () => {
      menu.classList.add("d-none")
    }

    const openMenu = () => {
      menu.classList.remove("d-none")
      search.value = ""
      filterOptions("")
      setTimeout(() => search.focus(), 0)
    }

    const filterOptions = (query) => {
      const cleanedQuery = query.toLowerCase().trim()
      let visibleCount = 0

      optionsWrap.querySelectorAll(".register-country-empty").forEach((node) => node.remove())

      options.forEach((option) => {
        const label = option.dataset.countryLabel.toLowerCase()
        const isVisible = label.includes(cleanedQuery)

        option.classList.toggle("d-none", !isVisible)

        if (isVisible) {
          visibleCount += 1
        }
      })

      if (visibleCount === 0) {
        const empty = document.createElement("div")
        empty.className = "register-country-empty"
        empty.textContent = "No countries found"
        optionsWrap.appendChild(empty)
      }
    }

    const chooseCountry = (option) => {
      selected.textContent = option.dataset.countryLabel
      hidden.value = option.dataset.countryCode
      hidden.setCustomValidity("")
      closeMenu()
    }

    toggle.addEventListener("click", () => {
      if (menu.classList.contains("d-none")) {
        openMenu()
      } else {
        closeMenu()
      }
    })

    search.addEventListener("input", () => {
      filterOptions(search.value)
    })

    search.addEventListener("keydown", (event) => {
      const visibleOptions = options.filter((option) => !option.classList.contains("d-none"))

      if (event.key === "Escape") {
        event.preventDefault()
        closeMenu()
      }

      if (event.key === "Enter" && visibleOptions.length > 0) {
        event.preventDefault()
        chooseCountry(visibleOptions[0])
      }
    })

    options.forEach((option) => {
      option.addEventListener("click", () => {
        chooseCountry(option)
      })
    })

    document.addEventListener("click", (event) => {
      if (!dropdown.contains(event.target)) {
        closeMenu()
      }
    })

    const form = dropdown.closest("form")

    if (form) {
      form.addEventListener("submit", (event) => {
        if (!hidden.value) {
          event.preventDefault()
          hidden.setCustomValidity("Please select a country.")
          toggle.focus()
          openMenu()
        }
      })
    }
  })
}

// Prevents login/register popups from closing when the user clicks outside the box or presses Escape
const setupStaticAuthModals = () => {
  const authModals = Array.from(document.querySelectorAll(".modal")).filter((modal) => {
    const id = modal.id.toLowerCase()
    const hasLoginForm = modal.querySelector("form[action='/login']")
    const hasRegisterForm = modal.querySelector("form[action='/register']")

    return id.includes("login") || id.includes("register") || hasLoginForm || hasRegisterForm
  })

  authModals.forEach((modal) => {
    modal.setAttribute("data-bs-backdrop", "static")
    modal.setAttribute("data-bs-keyboard", "false")

    if (window.bootstrap && window.bootstrap.Modal) {
      const existingInstance = window.bootstrap.Modal.getInstance(modal)

      if (existingInstance && modal.classList.contains("show")) {
        existingInstance._config.backdrop = "static"
        existingInstance._config.keyboard = false
      }

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
  })
}

onPageReady(() => {
  setupRegisterCountryDropdown()
  setupStaticAuthModals()
})