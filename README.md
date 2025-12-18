# PokeValue

PokeValue is a Ruby on Rails app for tracking sealed Pokémon TCG products, estimating portfolio value, and browsing sets with urgency indicators based on release dates.

It’s focused on **sealed product** (ETBs, booster boxes, mini tins, UPCs, etc.), with simple tools for collectors to see current holdings, unrealised P/L, and filter sets/products quickly.

## Features

### Portfolio

- Add holdings directly from a product page (`+ Add to Portfolio` modal).
- Track:
  - Era, set, product type, condition.
  - Quantity, cost per unit, total cost.
  - Value per unit, total value.
  - Unrealised **P/L** and **ROI %** per holding.
- Portfolio overview cards:
  - Total Cost
  - Total Value
  - Unrealised P/L
  - ROI %
- Client-side filtering on the holdings table:
  - Text search
  - Era, Set, Product Type, Condition
  - Cost / Value / P&L / ROI ranges
  - Purchase date range
- Links from holdings back to the relevant product page where possible.

### Sets & Products

- **Sets page**
  - Era sidebar (Mega Evolution, Scarlet & Violet, Sword & Shield).
  - Era badge that updates when era is switched.
  - Client-side filtering:
    - Era buttons.
    - Search bar for set names.
  - Grid of sets with set image and name.

- **Set detail page**
  - Top tiles:
    - Era, Release Date, Total Set Value, Cards/Secret, Urgency Level, etc.
  - **Urgency Level** tile computed from release date:
    - Very Low (0–6 months)  
    - Low (6–12 months)  
    - Medium (12–18 months)  
    - High (18–24 months)  
    - Very High (2–3 years)  
    - Out Of Print (>3 years)
  - Products grid (sealed items) with images and links to product detail pages.

- **Product detail page**
  - Set logo, product name, and a line like:  
    `Era · Set Name · Product Type`
  - Product info tiles:
    - Set, Era, Release Date
    - Product Type
    - Estimated Value
    - Listings count
  - `+ Add to Portfolio` button (opens auth modal if logged out, holding modal if logged in).

### Global Search

- Navbar **global search** box that queries `/search_index.json`.
- Searches across:
  - Sets (by name + era).
  - Products (by set, era, product type, etc.).
- Results dropdown grouped into:
  - **Sets**
  - **Products**
- Each result row shows:
  - Thumbnail
  - Label (set or product)
  - Subtitle (e.g. `Set · Era` or `Product · Set Name`)
  - Link to the set or product page.

### Marketplace, Auction, Raffle, Showcase

Currently **design/prototype pages** (no backend logic yet) with consistent UI:

- **Marketplace**
  - Filter card with:
    - Search
    - Location (Country)
    - Price min/max
    - Sort (newest/oldest/price)
    - Condition
  - Table layout ready for future data.

- **Auction**
  - Filters:
    - Search, Status, Location, Price min/max, Sort, Reserve status.
  - Auction table (Auctioneer, Product(s), Reserve Status, Bid, etc.)
  - “Host Auction” button placeholder.

- **Raffle**
  - Filters:
    - Search, Status, Location, Ticket Price min/max, Sort, Raffle Type.
  - Raffle table (Host, Prize, Ticket Price, Tickets Left, Ends, Actions).
  - “Host Raffle” button placeholder.

- **Showcase**
  - “Create a Post” card:
    - Heading
    - Image uploader
    - Description
  - “Community Posts” feed card (empty state for now).
  - Simple reply UI at the bottom (design only).

### Auth & Accounts

- Registration:
  - Username (5–15 chars, enforced client + server).
  - EU-only country dropdown (except for UK & Switzerland).
  - Strong password:
    - 12–20 chars.
    - Must include upper, lower, digit, and symbol.
    - Password cannot contain the username.
- Login:
  - Account lockout after repeated failed attempts (with lock window).
- Account page:
  - Simple “My Account” view for logged-in users.
- Navbar:
  - Shows “MyAccount” link.
  - Logged-in state: `username is logged in...` + Logout button.
  - Logged-out state: “Login/Register” button opens auth modal with tabs:
    - Login
    - Register

---

## Tech Stack

- **Backend:** Ruby on Rails (check `Gemfile` for exact version)
- **Ruby:** see `.ruby-version`
- **Database:** SQLite (development / test)
- **Frontend:**
  - ERB templates
  - Bootstrap 5 (CDN)
  - Small vanilla JS modules (no bundler/webpack)
- **Auth:** `has_secure_password` with bcrypt
- **Other:**
  - Importmap (`config/importmap.rb`)
  - Basic PWA files (`app/views/pwa/*`)

---

## Getting Started

### Prerequisites

- Ruby (version from `.ruby-version`)
- Bundler
- SQLite3
- Node/Yarn not strictly required if using importmap defaults.

### Setup

Clone the repo:

```bash
git clone https://github.com/DeanDolan/PokeValue.git
cd PokeValue
