import os
import json
import argparse
from typing import List, Dict, Any, Tuple

import numpy as np
import pandas as pd
from catboost import CatBoostRegressor


# These are the exact columns that will be used as input features for the machine learning model.
# The order matters because the same feature list is saved into model_meta.json after training.
# Numeric features such as lag values, rolling averages, dates and release-age values help the model
# understand price movement over time.
# Categorical features such as Set Name, Product Name, Product Category and Era help the model learn
# differences between products and Pokémon eras.
FEATURE_COLS = [
    "lag_1",
    "lag_3",
    "lag_6",
    "lag_12",
    "roll_3_mean",
    "roll_6_mean",
    "roll_12_mean",
    "roll_6_std",
    "roll_12_std",
    "month_of_year",
    "year",
    "months_since_release",
    "Set Name",
    "Product Name",
    "Product Category",
    "Era",
]


def to_month_start(s: pd.Series) -> pd.Series:
    # Converts a date column into the first day of that date's month.
    # This is done because the forecasting model works with monthly product values rather than exact daily values.
    # Example: 15/03/2025 becomes 01/03/2025.
    # errors="coerce" means invalid dates become NaT instead of crashing the script.
    return pd.to_datetime(s, errors="coerce").dt.to_period("M").dt.to_timestamp(how="start")


def std_last(arr: np.ndarray) -> float:
    # Calculates the standard deviation for a group of recent values.
    # Standard deviation is used to measure how much the product value has been moving up and down.
    # If there is fewer than 2 values, standard deviation is not useful, so the function returns 0.0.
    if arr.size < 2:
        return 0.0

    # ddof=1 calculates sample standard deviation, which is normally used when working from observed data.
    return float(np.std(arr, ddof=1)) if arr.size >= 2 else 0.0


def lag_value(y: np.ndarray, k: int) -> float:
    # Returns a previous product value from the price history.
    # lag_1 means the most recent previous value.
    # lag_3 means the value from 3 months ago.
    # lag_6 means the value from 6 months ago.
    # lag_12 means the value from 12 months ago.
    if y.size == 0:
        return 0.0

    # If there is enough history, return the value from exactly k months ago.
    if y.size >= k:
        return float(y[-k])

    # If there is not enough history for that lag, use the latest available value instead.
    # This prevents the model training from failing when newer products have shorter history.
    return float(y[-1])


def build_row(
    y_hist: List[float],
    target_month: pd.Timestamp,
    set_name: str,
    product_name: str,
    product_category: str,
    era: str,
    set_release_date: pd.Timestamp,
) -> Dict[str, Any]:
    # Builds one training row for the model.
    # Each row contains the information the model is allowed to know before predicting the target month value.
    # y_hist is the product's previous value history.
    # target_month is the month the model is trying to predict.
    # set/product/category/era are categorical details used by CatBoost.
    # set_release_date allows the model to know how old the set is when making the prediction.

    # Convert the historical values into a NumPy array so mathematical calculations are easier.
    y = np.array(y_hist, dtype=float)

    # If there is no history, a training row cannot be built.
    if y.size == 0:
        return {}

    # Rolling averages help the model understand recent trend behaviour.
    # roll_3 is the average of the last 3 known monthly values.
    # If there are fewer than 3 values, it averages all available values instead.
    roll_3 = float(np.mean(y[-3:])) if y.size >= 3 else float(np.mean(y))

    # roll_6 is the average of the last 6 known monthly values.
    # If there are fewer than 6 values, it averages all available values instead.
    roll_6 = float(np.mean(y[-6:])) if y.size >= 6 else float(np.mean(y))

    # roll_12 is the average of all values passed into this function.
    # In this script, y_hist is already limited to the last 12 values before being passed in.
    roll_12 = float(np.mean(y)) if y.size >= 1 else 0.0

    # Rolling standard deviation measures volatility.
    # Higher standard deviation means the product value has been changing more aggressively.
    roll_6_std = std_last(y[-6:]) if y.size >= 2 else 0.0
    roll_12_std = std_last(y[-12:]) if y.size >= 2 else 0.0

    # Default value used when no release date is available.
    # -1 is used so the model can still train even when the spreadsheet does not contain this information.
    months_since_release = -1

    # If the set release date exists, calculate how many months old the set is at the target month.
    if pd.notna(set_release_date):
        # Convert the release date to the first day of the release month.
        rel_m = pd.to_datetime(set_release_date).to_period("M").to_timestamp(how="start")

        # Calculate total months between the release month and the target prediction month.
        months_since_release = int((target_month.year - rel_m.year) * 12 + (target_month.month - rel_m.month))

    # Return the finished feature row.
    # The keys must match FEATURE_COLS so the model receives the correct columns.
    return {
        "lag_1": lag_value(y, 1),
        "lag_3": lag_value(y, 3),
        "lag_6": lag_value(y, 6),
        "lag_12": lag_value(y, 12),
        "roll_3_mean": roll_3,
        "roll_6_mean": roll_6,
        "roll_12_mean": roll_12,
        "roll_6_std": float(roll_6_std),
        "roll_12_std": float(roll_12_std),
        "month_of_year": int(target_month.month),
        "year": int(target_month.year),
        "months_since_release": int(months_since_release),
        "Set Name": set_name,
        "Product Name": product_name,
        "Product Category": product_category,
        "Era": era,
    }


def load_excel(xlsx_path: str) -> pd.DataFrame:
    # Loads the historical product value spreadsheet into a pandas DataFrame.
    # The spreadsheet is the training dataset used to teach the model how sealed product values changed over time.

    # Stop immediately if the Excel file path is wrong.
    if not os.path.exists(xlsx_path):
        raise RuntimeError(f"Excel file not found: {xlsx_path}")

    # Read the Excel file using openpyxl.
    # openpyxl is required for reading .xlsx files.
    df = pd.read_excel(xlsx_path, engine="openpyxl")

    # These columns are required because the model cannot train without dates, product identity and product value.
    required = ["Date", "Set Name", "Product Name", "Product Value"]

    # Check that each required column exists in the spreadsheet.
    # If a column is missing, stop with a clear error message.
    for c in required:
        if c not in df.columns:
            raise RuntimeError(f"Excel is missing required column: '{c}'")

    # Convert the Date column into pandas datetime format.
    # dayfirst=True is useful for Irish/European date formatting such as 13/05/2026.
    # Invalid dates become NaT instead of crashing.
    df["Date"] = pd.to_datetime(df["Date"], dayfirst=True, errors="coerce")

    # Convert product values into numbers.
    # Invalid values become NaN and are removed later.
    df["Product Value"] = pd.to_numeric(df["Product Value"], errors="coerce")

    # Set Release Date is useful for calculating months_since_release.
    # If the spreadsheet has the column, convert it into datetime.
    if "Set Release Date" in df.columns:
        df["Set Release Date"] = pd.to_datetime(df["Set Release Date"], dayfirst=True, errors="coerce")
    else:
        # If the spreadsheet does not include Set Release Date, create the column with missing date values.
        df["Set Release Date"] = pd.NaT

    # Product Category is useful as a categorical feature.
    # If missing, create it as an empty string column so the model can still train.
    if "Product Category" not in df.columns:
        df["Product Category"] = ""

    # Era is also used as a categorical feature.
    # If missing, create it as an empty string column so the model can still train.
    if "Era" not in df.columns:
        df["Era"] = ""

    # Fill missing Product Category and Era values with empty strings.
    # CatBoost expects categorical features to be strings, so they are converted here.
    df["Product Category"] = df["Product Category"].fillna("").astype(str)
    df["Era"] = df["Era"].fillna("").astype(str)

    # Remove rows that cannot be used for training.
    # Rows without a date, set name, product name or product value are not useful for supervised learning.
    df = df.dropna(subset=["Date", "Set Name", "Product Name", "Product Value"])

    # Create a month column so all values can be grouped by month.
    # This avoids the model treating multiple dates in the same month as separate time periods.
    df["month"] = to_month_start(df["Date"])

    # Return the cleaned spreadsheet data.
    return df


def build_supervised(df: pd.DataFrame) -> Tuple[pd.DataFrame, pd.Series]:
    # Converts the cleaned spreadsheet into supervised machine learning data.
    # Supervised learning means the model is given input features X and known target answers y.
    # In this case:
    # X = historical product information before a month
    # y = actual product value for that month

    # rows will store all feature dictionaries.
    rows = []

    # targets will store the actual values the model is trying to learn to predict.
    targets = []

    # Group by product identity and release information.
    # Each product needs to be processed separately so its history does not get mixed with another product.
    grp_cols = ["Set Name", "Product Name", "Product Category", "Era", "Set Release Date"]

    # Loop through every unique product group in the spreadsheet.
    for (set_name, product_name, product_category, era, set_release_date), g in df.groupby(grp_cols, dropna=False):
        # Group duplicate values within the same month by taking the average Product Value.
        # This gives one monthly value per product per month.
        g2 = g.groupby("month", as_index=False)["Product Value"].mean().rename(columns={"Product Value": "value"})

        # Sort the product's values by month so the time-series order is correct.
        g2 = g2.sort_values("month").reset_index(drop=True)

        # At least 2 monthly values are needed:
        # one or more previous values as history and one value to predict.
        if len(g2) < 2:
            continue

        # Extract the month list and monthly product values.
        months = g2["month"].tolist()
        values = g2["value"].astype(float).tolist()

        # Start from index 1 because index 0 has no previous value to learn from.
        for i in range(1, len(months)):
            # Historical values are all values before the target month.
            hist_vals = values[:i]

            # This is the actual product value for the target month.
            target_val = float(values[i])

            # Convert the target month to a clean month-start timestamp.
            target_month = pd.to_datetime(months[i]).to_period("M").to_timestamp(how="start")

            # Build the feature row using only previous historical values.
            # hist_vals[-12:] limits the model input to the latest 12 months of history.
            feat = build_row(
                y_hist=hist_vals[-12:],
                target_month=target_month,
                set_name=str(set_name),
                product_name=str(product_name),
                product_category=str(product_category),
                era=str(era),
                set_release_date=set_release_date,
            )

            # If build_row returned an empty dictionary, skip this row.
            if not feat:
                continue

            # Store the feature row and its correct target value.
            rows.append(feat)
            targets.append(target_val)

    # If no rows were created, the spreadsheet does not contain enough usable history.
    if not rows:
        raise RuntimeError("No supervised rows could be built (not enough history in the spreadsheet).")

    # Convert feature dictionaries into a DataFrame using the exact feature order defined in FEATURE_COLS.
    X = pd.DataFrame(rows, columns=FEATURE_COLS)

    # Convert target values into a pandas Series called y.
    y = pd.Series(targets, name="y")

    # Return model inputs and target outputs.
    return X, y


def main():
    # Main function for training the forecasting model.
    # This function is only run when the script is executed directly.

    # Create the command-line argument parser.
    ap = argparse.ArgumentParser()

    # Required path to the Excel spreadsheet containing historical product values.
    ap.add_argument("--xlsx", required=True)

    # Output path for the trained CatBoost model file.
    # Default file name is model.cbm.
    ap.add_argument("--out-model", default="model.cbm")

    # Output path for the metadata JSON file.
    # This stores feature names and categorical feature information needed later by the forecasting service.
    ap.add_argument("--out-meta", default="model_meta.json")

    # Random seed used to make training more reproducible.
    ap.add_argument("--seed", type=int, default=42)

    # Parse the command-line arguments.
    args = ap.parse_args()

    # Load and clean the historical product value spreadsheet.
    df = load_excel(args.xlsx)

    # Convert the cleaned spreadsheet into model features X and target values y.
    X, y = build_supervised(df)

    # These columns are categorical features.
    # CatBoost can handle categorical columns directly when their column indexes are provided.
    cat_cols = ["Set Name", "Product Name", "Product Category", "Era"]

    # Find the numeric index position of each categorical feature column.
    cat_idx = [X.columns.get_loc(c) for c in cat_cols]

    # Copy X before modifying categorical columns.
    # This avoids changing the original DataFrame unexpectedly.
    X = X.copy()

    # Make sure all categorical feature values are strings and do not contain null values.
    for c in cat_cols:
        X[c] = X[c].fillna("").astype(str)

    # Create the CatBoost regression model.
    # Regression is used because the model predicts a numeric value: future product price/value.
    model = CatBoostRegressor(
        # RMSE is a common loss function for numeric prediction problems.
        loss_function="RMSE",

        # Random seed helps keep training results more consistent across runs.
        random_seed=args.seed,

        # Tree depth controls model complexity.
        # A higher depth can learn more complex patterns but may overfit if the dataset is small.
        depth=8,

        # Learning rate controls how quickly the model updates during training.
        learning_rate=0.06,

        # Number of boosting iterations.
        # More iterations can improve learning but also take longer.
        iterations=1200,

        # L2 regularisation helps reduce overfitting.
        l2_leaf_reg=6.0,

        # Print training progress every 200 iterations.
        verbose=200,
    )

    # Train the model using the feature table X and target values y.
    # cat_features tells CatBoost which columns are categorical.
    model.fit(X, y, cat_features=cat_idx)

    # Save the trained model to disk.
    # This file is later loaded by the forecasting service to make predictions.
    model.save_model(args.out_model)

    # Store important metadata about the trained model.
    # The forecasting service needs this information so it can build prediction rows in the same format.
    meta = {
        "feature_cols": FEATURE_COLS,
        "cat_features": cat_cols,
        "cat_feature_indices": cat_idx,
        "training_rows": int(len(X)),
    }

    # Write the metadata to a JSON file.
    with open(args.out_meta, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    # Print confirmation messages after successful training.
    print(f"Saved model -> {args.out_model}")
    print(f"Saved meta  -> {args.out_meta}")
    print(f"Rows trained: {len(X)}")


# This makes sure main() only runs when this file is executed directly.
# It prevents the training process from starting automatically if this file is imported by another Python file.
if __name__ == "__main__":
    main()