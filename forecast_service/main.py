# Python FastAPI service file
# Starts the API app, loads the Excel dataset, loads the trained CatBoost model, exposes /health and /forecast endpoints, builds monthly product value history, generates 60 months of predictions, and returns JSON to Rails.

import os  # Used for file paths and environment variables
import json  # Used to read model_meta.json
import difflib  # Used to suggest close product-name matches when an exact product is not found
from typing import Optional, Dict, Any, List  # Used for type hints

import numpy as np  # Used for numerical calculations such as averages, standard deviation and arrays
import pandas as pd  # Used to load, clean, filter and prepare the Excel dataset
from fastapi import FastAPI, HTTPException  # Used to create the API app and return API errors
from catboost import CatBoostRegressor  # Used to load the trained CatBoost forecasting model

app = FastAPI(title="PokeValue Forecast Service", version="2.0.3")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

EXCEL_PATH = os.getenv("FORECAST_XLSX_PATH", "Pokemon_Future_Forecasting.xlsx")
MODEL_PATH = os.getenv("FORECAST_MODEL_PATH", "model.cbm")
META_PATH = os.getenv("FORECAST_META_PATH", "model_meta.json")

_df = None
_model = None
_meta = None
_startup_error: Optional[str] = None


# Converts a relative file path into a full path inside the forecasting service folder.
def resolve_path(p: str) -> str:
    if not p:
        return p
    if os.path.isabs(p):
        return p
    return os.path.join(BASE_DIR, p)


# Converts dates into the first day of their month for monthly forecasting.
def to_month_start(s):
    return pd.to_datetime(s, errors="coerce").dt.to_period("M").dt.to_timestamp(how="start")


# Loads and cleans the historical Excel dataset used for forecasting.
def load_data() -> pd.DataFrame:
    path = resolve_path(EXCEL_PATH)
    if not os.path.exists(path):
        raise RuntimeError(f"Excel file not found: {path}")

    df = pd.read_excel(path, engine="openpyxl")

    if "Date" not in df.columns:
        raise RuntimeError("Excel is missing required column: 'Date'")
    if "Set Name" not in df.columns:
        raise RuntimeError("Excel is missing required column: 'Set Name'")
    if "Product Name" not in df.columns:
        raise RuntimeError("Excel is missing required column: 'Product Name'")
    if "Product Value" not in df.columns:
        raise RuntimeError("Excel is missing required column: 'Product Value'")

    df["Date"] = pd.to_datetime(df["Date"], dayfirst=True, errors="coerce")
    df["Product Value"] = pd.to_numeric(df["Product Value"], errors="coerce")

    if "Set Release Date" in df.columns:
        df["Set Release Date"] = pd.to_datetime(df["Set Release Date"], dayfirst=True, errors="coerce")
    else:
        df["Set Release Date"] = pd.NaT

    if "Product Category" not in df.columns:
        df["Product Category"] = ""
    if "Era" not in df.columns:
        df["Era"] = ""

    df = df.dropna(subset=["Date", "Set Name", "Product Name"])
    df = df.dropna(subset=["Product Value"])

    df["Product Category"] = df["Product Category"].fillna("").astype(str)
    df["Era"] = df["Era"].fillna("").astype(str)

    df["month"] = to_month_start(df["Date"])

    df["set_name_ci"] = df["Set Name"].astype(str).str.casefold().str.strip()
    df["product_name_ci"] = df["Product Name"].astype(str).str.casefold().str.strip()
    df["product_category_ci"] = df["Product Category"].astype(str).str.casefold().str.strip()

    return df


# Loads the trained CatBoost model and its metadata file.
def load_model():
    model_path = resolve_path(MODEL_PATH)
    meta_path = resolve_path(META_PATH)

    if not os.path.exists(model_path):
        return None, None
    if not os.path.exists(meta_path):
        return None, None

    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)

    model = CatBoostRegressor()
    model.load_model(model_path)
    return model, meta


# Converts date/value columns into JSON-friendly chart points.
def to_points(dates: pd.Series, values: pd.Series) -> List[Dict[str, Any]]:
    out = []
    for d, v in zip(dates, values):
        if pd.isna(d) or pd.isna(v):
            continue
        out.append({"date": pd.to_datetime(d).strftime("%Y-%m-%d"), "value": round(float(v), 2)})
    return out


# Builds monthly product value history from the selected product rows.
def build_monthly_price_history(df_sel: pd.DataFrame) -> pd.DataFrame:
    if "month" not in df_sel.columns:
        df_sel = df_sel.copy()
        df_sel["month"] = to_month_start(df_sel["Date"])

    hist = df_sel.groupby("month", as_index=False)["Product Value"].mean()
    hist = hist.rename(columns={"Product Value": "value"})
    hist["month"] = to_month_start(hist["month"])
    return hist.sort_values("month").reset_index(drop=True)


# Builds the current forecasting state using recent historical values.
def compute_state(window: List[float]) -> Dict[str, Any]:
    y = np.array(window, dtype=float)

    def lag(k: int) -> float:
        if len(y) >= k:
            return float(y[-k])
        return float(y[-1])

    roll_3_mean = float(np.mean(y[-3:])) if len(y) >= 3 else float(np.mean(y))
    roll_6_mean = float(np.mean(y[-6:])) if len(y) >= 6 else float(np.mean(y))
    roll_12_mean = float(np.mean(y)) if len(y) >= 1 else 0.0

    def std_last(n: int) -> float:
        if len(y) < 2:
            return 0.0
        arr = y[-n:] if len(y) >= n else y
        return float(np.std(arr, ddof=1)) if len(arr) >= 2 else 0.0

    return {
        "lag_1": lag(1),
        "lag_3": lag(3),
        "lag_6": lag(6),
        "lag_12": lag(12),
        "roll_3_mean": roll_3_mean,
        "roll_6_mean": roll_6_mean,
        "roll_12_mean": roll_12_mean,
        "roll_6_std": std_last(6),
        "roll_12_std": std_last(12),
        "window": list(map(float, window)),
    }


# Updates the forecasting state after each predicted monthly value.
def update_state(state: Dict[str, Any], new_value: float) -> Dict[str, Any]:
    w = state["window"]
    w.append(float(new_value))
    if len(w) > 12:
        w = w[-12:]
    return compute_state(w)


# Builds one prediction row using the latest forecasting state and product metadata.
def features_from_state(
    last_known: Dict[str, Any],
    target_month: pd.Timestamp,
    set_name: str,
    product_name: str,
    product_category: str,
    era: str,
    set_release_date: pd.Timestamp,
) -> Dict[str, Any]:
    months_since_release = -1
    if pd.notna(set_release_date):
        rel_m = pd.to_datetime(set_release_date).to_period("M").to_timestamp(how="start")
        months_since_release = int((target_month.year - rel_m.year) * 12 + (target_month.month - rel_m.month))

    return {
        "lag_1": float(last_known["lag_1"]),
        "lag_3": float(last_known["lag_3"]),
        "lag_6": float(last_known["lag_6"]),
        "lag_12": float(last_known["lag_12"]),
        "roll_3_mean": float(last_known["roll_3_mean"]),
        "roll_6_mean": float(last_known["roll_6_mean"]),
        "roll_12_mean": float(last_known["roll_12_mean"]),
        "roll_6_std": float(last_known["roll_6_std"]),
        "roll_12_std": float(last_known["roll_12_std"]),
        "month_of_year": int(target_month.month),
        "year": int(target_month.year),
        "months_since_release": months_since_release,
        "Set Name": set_name,
        "Product Name": product_name,
        "Product Category": product_category,
        "Era": era,
    }


# Generates monthly forecast predictions using the trained CatBoost model.
def generate_forecast(
    hist_months: List[pd.Timestamp],
    hist_values: List[float],
    set_name: str,
    product_name: str,
    product_category: str,
    era: str,
    set_release_date: pd.Timestamp,
    months_ahead: int = 60,
) -> List[Dict[str, Any]]:
    if _model is None or _meta is None:
        raise HTTPException(status_code=500, detail="Model not loaded (missing model.cbm or model_meta.json)")

    feature_cols = _meta["feature_cols"]

    window = hist_values[-12:] if len(hist_values) >= 12 else hist_values[:]
    state = compute_state(window)

    last_month = pd.to_datetime(hist_months[-1]).to_period("M").to_timestamp(how="start")
    current_month = last_month

    forecasts = []
    for _ in range(months_ahead):
        target_month = (current_month + pd.offsets.MonthBegin(1)).to_period("M").to_timestamp(how="start")

        feat = features_from_state(
            last_known=state,
            target_month=target_month,
            set_name=set_name,
            product_name=product_name,
            product_category=product_category,
            era=era,
            set_release_date=set_release_date,
        )

        row = pd.DataFrame([{c: feat.get(c, np.nan) for c in feature_cols}])
        yhat = float(_model.predict(row)[0])
        yhat = max(0.0, yhat)

        forecasts.append({"date": target_month.strftime("%Y-%m-%d"), "value": round(yhat, 2)})

        state = update_state(state, yhat)
        current_month = target_month

    return forecasts


# Runs when the FastAPI service starts and loads the dataset, model and metadata.
@app.on_event("startup")
def startup():
    global _df, _model, _meta, _startup_error
    try:
        _df = load_data()
        _model, _meta = load_model()
        _startup_error = None
    except Exception as e:
        _startup_error = f"{type(e).__name__}: {str(e)}"
        _df = None
        _model = None
        _meta = None


# Health endpoint used to check whether the forecasting service is running correctly.
@app.get("/health")
def health():
    return {
        "ok": _startup_error is None,
        "model_loaded": _model is not None and _meta is not None,
        "data_loaded": _df is not None,
        "error": _startup_error,
    }


# Forecast endpoint called by Rails to return history, forecast values and milestones as JSON.
@app.get("/forecast")
def forecast(
    set_name: str,
    product_name: Optional[str] = None,
    product_category: Optional[str] = None,
) -> Dict[str, Any]:
    if _startup_error is not None:
        raise HTTPException(status_code=500, detail=_startup_error)
    if _df is None:
        raise HTTPException(status_code=500, detail="Data not loaded")

    set_ci = str(set_name).casefold().strip()
    name_ci = str(product_name).casefold().strip() if product_name else None
    cat_ci = str(product_category).casefold().strip() if product_category else None

    df = _df[_df["set_name_ci"] == set_ci].copy()
    if df.empty:
        raise HTTPException(status_code=404, detail=f"Set not found: '{set_name}'")

    df2 = pd.DataFrame()
    if name_ci:
        df2 = df[df["product_name_ci"] == name_ci].copy()

    if df2.empty and cat_ci:
        df2 = df[df["product_category_ci"] == cat_ci].copy()

    if df2.empty and name_ci:
        options = sorted(df["Product Name"].dropna().unique().tolist())
        guesses = difflib.get_close_matches(product_name, options, n=5, cutoff=0.45)
        raise HTTPException(status_code=404, detail={"error": "Product not found in set", "guesses": guesses})

    if df2.empty:
        raise HTTPException(status_code=404, detail="No matching product found")

    set_name_exact = str(df2["Set Name"].iloc[0])
    product_name_exact = str(df2["Product Name"].iloc[0])
    product_category_exact = str(df2["Product Category"].iloc[0]) if "Product Category" in df2.columns else ""
    era_exact = str(df2["Era"].iloc[0]) if "Era" in df2.columns else ""
    set_release_date = df2["Set Release Date"].iloc[0] if "Set Release Date" in df2.columns else pd.NaT

    hist = build_monthly_price_history(df2)
    if hist.empty:
        raise HTTPException(status_code=404, detail="No Product Value history found")

    history_points = to_points(hist["month"], hist["value"])

    forecasts = generate_forecast(
        hist_months=hist["month"].tolist(),
        hist_values=hist["value"].tolist(),
        set_name=set_name_exact,
        product_name=product_name_exact,
        product_category=product_category_exact,
        era=era_exact,
        set_release_date=set_release_date,
        months_ahead=60,
    )

    # Picks a forecast value for a milestone such as 6 months, 1 year, 3 years or 5 years.
    def pick(points, months):
        if not points or months <= 0 or months > len(points):
            return None
        return points[months - 1]["value"]

    # Stores the key forecast milestones returned to Rails.
    milestones = {
        "6m": pick(forecasts, 6),
        "1y": pick(forecasts, 12),
        "3y": pick(forecasts, 36),
        "5y": pick(forecasts, 60),
    }

    # Returns the final JSON response that Rails sends back to the product page.
    return {
        "set_name": set_name_exact,
        "product_name": product_name_exact,
        "product_category": product_category_exact,
        "currency": "EUR",
        "as_of": history_points[-1]["date"] if history_points else None,
        "history": history_points,
        "forecast": forecasts,
        "milestones": milestones,
    }