# PokéValue

PokéValue is a Ruby on Rails web application built for tracking, valuing, forecasting, buying, selling, auctioning, raffling, and discussing sealed Pokémon products from a European collector and investor perspective.

The application focuses on sealed Pokémon products such as Elite Trainer Boxes, Booster Boxes, Booster Bundles, Ultra Premium Collections, Super Premium Collections, and other sealed items. It is designed around EU market needs, where pricing and availability can differ from US-focused platforms.

## Main Purpose

PokéValue was created to give Pokémon sealed product collectors and investors one platform where they can:

- Track their portfolio holdings
- View estimated product values
- Monitor profit, loss, ROI, and total portfolio value/cost
- Add products to a watchlist
- View future product value projections
- List products for sale in a marketplace
- Create and bid on auctions
- Host and enter raffles
- Interact through a community page
- Manage their own account, badges, listings, auctions, raffles, and saved addresses

## Key Features

### Portfolio

Users can add sealed Pokémon products to their portfolio and track:

- Quantity owned
- Cost per unit
- Estimated value per unit
- Total cost
- Total value
- Unrealised profit/loss
- ROI percentage
- Realised profit/loss
- Portfolio history through summary entries
- Portfolio metrics through chart data

### Sets and Product Pages

The application includes pages for Pokémon sets and sealed products.

Users can:

- View all sets
- Search and filter through sets
- Open a set page
- View products belonging to that set
- Open individual product pages
- View product details
- Add products to their portfolio
- Add products to their watchlist
- Open future projections for a selected product

### Future Projections

The forecasting feature uses a separate Python FastAPI service.

The Rails application sends product details to the forecasting service, which loads historical product value data from an Excel spreadsheet and returns forecasted values as JSON.

The product page displays forecast values for:

- 6 months
- 1 year
- 3 years
- 5 years

The frontend uses Stimulus and Chart.js to update the forecasting chart when the user clicks between these time periods.

### Marketplace

Users can:

- View current and sold marketplace listings
- Filter marketplace listings
- Create a listing
- View listing details
- Buy products from other users
- Confirm payment
- Delete their own listings
- Admin users can manage listings where required

### Auctions

Users can:

- View active, ended, and sold auctions
- Create auction listings
- Bid on auctions
- View auction details
- Confirm and verify payment

### Raffles

Users can:

- View raffles, mini raffles, completed raffles, and incompleted raffles
- Host raffles
- Buy raffle tickets
- Return tickets where allowed
- Run the raffle once all tickets are sold
- Use a spin-the-wheel style winner selection

### Community

Users can:

- Create posts in community channels
- Delete/Edit their own posts
- Comment on posts
- React to posts with emojis
- React to comments with emojis

### Account Page

Users can view and manage:

- Username
- Country
- Badges
- Marketplace listings
- Auctions
- Watchlist
- Saved addresses

### Admin Area

Admin users can access:

- Products
- Sets

Admins can update product values, update set values, and delete auctions/listings/raffles if necessary.

## Tech Stack

### Main Web Application

- Ruby on Rails 8
- Ruby
- Sqlite3
- ERB views
- CSS
- JavaScript
- Stimulus
- Turbo
- Bootstrap 5.3
- Chart.js
- Active Storage

### Forecasting Service

- Python
- FastAPI
- Uvicorn
- pandas
- NumPy
- CatBoost
- JSON
- Microsoft Excel

### Database

Sqlite is used to store users, products, holdings, marketplace listings, purchases, transactions, auctions, bids, raffles, raffle tickets, community posts, comments, reactions, watchlists, saved addresses, and admin-related data.

## Project Structure

```text
app/
  assets/
    images/
    stylesheets/
  controllers/
  helpers/
  javascript/
    controllers/
  models/
  services/
  views/

config/
  routes.rb
  importmap.rb
  sets.json

db/
  migrate/
  schema.rb
  seeds.rb

forecasting_service/
  main.py
  train_model.py
  model.cbm
  model_meta.json
  Pokemon_Future_Forecasting.xlsx
  requirements.txt
  README.md
```

## Important Rails Files

```
config/routes.rb
app/controllers/product_controller.rb
app/controllers/forecasts_controller.rb
app/controllers/portfolios_controller.rb
app/controllers/holdings_controller.rb
app/controllers/marketplace_listings_controller.rb
app/controllers/auctions_controller.rb
app/controllers/raffles_controller.rb
app/controllers/accounts_controller.rb
app/controllers/watchlists_controller.rb
app/views/pages/product.html.erb
app/views/portfolios/index.html.erb
app/views/marketplace_listings/index.html.erb
app/views/auctions/show.html.erb
app/views/raffles/show.html.erb
app/javascript/controllers/forecast_controller.js
app/javascript/controllers/metrics_controller.js
app/javascript/controllers/portfolio_filters_controller.js
```

## Forecasting Flow

The forecasting feature works through Rails, JavaScript, and Python.

```
User opens a product page
→ User clicks Future Projections
→ The forecast modal opens
→ Stimulus reads the product data attributes from the button
→ forecast_controller.js sends a GET request to /forecast
→ config/routes.rb sends /forecast to ForecastsController#show
→ ForecastsController calls the Python FastAPI service using Net::HTTP
→ main.py receives the request at /forecast
→ main.py loads the Excel dataset and CatBoost model
→ main.py returns history, forecast, milestones, and as_of values as JSON
→ Rails sends the JSON back to the browser
→ forecast_controller.js updates the milestone values and redraws the Chart.js line chart
```

## Forecast Chart Buttons

The 6 month, 1 year, 3 years, and 5 years buttons do not request new data from Rails each time they are clicked.

The full 60-month forecast is already returned from the Python service. When a user clicks one of the buttons, the Stimulus controller changes the active horizon, slices the forecast array to the correct number of months, destroys the old chart, and redraws the Chart.js graph.

```
6m = first 6 forecast months
1y = first 12 forecast months
3y = first 36 forecast months
5y = first 60 forecast months
```

## Running the Rails Application

Install dependencies:

```bash
bundle install
```

Windows PowerShell:

```
ruby bin/rails server -p 3000
```

The Rails application will usually run at:

http://localhost:3000

## Running the Forecasting Service

Go into the forecasting service folder:

```powershell
cd forecasting_service
```

Install Python dependencies:

```powershell
pip install -r requirements.txt
```

Start the FastAPI service:

```powershell
python -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

The forecasting service will run at:

http://127.0.0.1:8000


The Rails app expects the forecasting service to be available at:

http://127.0.0.1:8000/forecast

## Security Features

PokéValue includes:

- Password-based authentication
- Session handling
- Admin MFA flow
- Filtered parameter logging
- Rack Attack configuration
- Role-based admin access

## Author

Developed by Dean Dolan 
