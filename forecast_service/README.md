# PokéValue Forecasting Service

This folder contains the separate Python forecasting service used by PokéValue.

The main Rails application uses this service for the Future Projections feature on product pages. Rails sends product details to this service, the service checks the historical product value dataset, generates forecast values using a trained CatBoost model, and returns the result as JSON.

## Purpose

The forecasting service is responsible for predicting future sealed Pokémon product values for:

- 6 months
- 1 year
- 3 years
- 5 years

These predictions are shown on the product page inside the Future Projections modal. The Rails app displays the returned forecast values using Stimulus and Chart.js.

## Files

```
forecasting_service/
  main.py
  train_model.py
  model.cbm
  model_meta.json
  Pokemon_Future_Forecasting.xlsx
  requirements.txt
  README.md
```

## File Descriptions

### main.py

`main.py` is the main FastAPI service file.

It:

- Creates the FastAPI app
- Loads the Excel forecasting dataset
- Loads the trained CatBoost model
- Exposes the `/health` endpoint
- Exposes the `/forecast` endpoint
- Builds monthly product value history
- Generates future monthly predictions
- Returns forecast data to Rails as JSON

### train_model.py

`train_model.py` is the model training script.

It is used to train the CatBoost forecasting model from the historical Excel dataset. After training, it creates the generated model files used by `main.py`.

### model.cbm

`model.cbm` is the generated CatBoost model file.

It is created by running the training script. The FastAPI service loads this file to make product value predictions.

### model_meta.json

`model_meta.json` is a generated metadata file.

It stores details such as the feature columns used during training so that the prediction data is built in the same structure when the service runs.

### Pokemon_Future_Forecasting.xlsx

`Pokemon_Future_Forecasting.xlsx` is the historical dataset used by the forecasting service.

It contains historical sealed Pokémon product value data. The service reads this file, filters it by set and product, builds monthly history, and uses that history to generate predictions.

Important columns include:

- Date
- Product Category
- Era
- Set Name
- Product Name
- Product Value
- Set Release Date

### requirements.txt

`requirements.txt` lists the Python packages needed to run the forecasting service.

The main packages are:

- FastAPI
- Uvicorn
- pandas
- NumPy
- CatBoost
- openpyxl

## Technologies Used

- Python
- FastAPI
- Uvicorn
- pandas
- NumPy
- CatBoost
- openpyxl
- JSON
- Microsoft Excel

## How Rails Connects to the Forecasting Service

The Rails app does not calculate the forecast directly.

Instead, Rails sends a request to the Python service.

```
User opens a product page
→ User clicks Future Projections
→ forecast_controller.js sends a request to Rails /forecast
→ config/routes.rb sends /forecast to ForecastsController#show
→ ForecastsController uses Net::HTTP to call http://127.0.0.1:8000/forecast
→ main.py receives the request
→ main.py loads the matching product history
→ main.py generates forecast values
→ main.py returns JSON to Rails
→ Rails returns the JSON to the browser
→ forecast_controller.js updates the milestone values and Chart.js graph
```

## Forecast JSON Response

The `/forecast` endpoint returns data similar to this:

```json
{
  "set_name": "Example Set",
  "product_name": "Example Product",
  "product_category": "ETB",
  "currency": "EUR",
  "as_of": "2026-05-01",
  "history": [
    { "date": "2025-01-01", "value": 50.00 }
  ],
  "forecast": [
    { "date": "2026-06-01", "value": 58.25 }
  ],
  "milestones": {
    "6m": 60.00,
    "1y": 68.50,
    "3y": 95.75,
    "5y": 130.25
  }
}
```

## Forecast Chart Buttons

The 6 month, 1 year, 3 years, and 5 years buttons do not call the Python service again each time they are clicked.

The service already returns a full 60-month forecast. The JavaScript controller stores that forecast data, then changes the chart by slicing the forecast array:

```
6m = first 6 forecast months
1y = first 12 forecast months
3y = first 36 forecast months
5y = first 60 forecast months
```

After the user clicks a button, the old Chart.js graph is destroyed and a new graph is drawn using the selected time range.

## Run the Forecasting Service

Open PowerShell and move into the forecasting service folder:

```powershell
cd C:\Users\deand\OneDrive\Desktop\PokeValueApp\forecasting_service
```

Install the Python dependencies:

```powershell
pip install -r requirements.txt
```

Start the FastAPI service:

```powershell
python -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

The forecasting service will run at:

http://127.0.0.1:8000

The forecast endpoint will be available at:

http://127.0.0.1:8000/forecast

The health endpoint will be available at:

http://127.0.0.1:8000/health

## Important Notes

- The Rails app must be running separately.
- The forecasting service must also be running separately.
- Rails expects the forecasting service to run on port `8000`.
- If the forecasting service is turned off, the Future Projections feature will show an unavailable message.
- The forecast values are estimates only and should not be treated as guaranteed investment results.

## Author

Developed by Dean Dolan
