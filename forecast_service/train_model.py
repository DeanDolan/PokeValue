# Python training script

import os  # Used to check whether the Excel file path exists
import json  # Used to save model metadata into model_meta.json
import argparse  # Used to read command-line arguments when running the script
from typing import List, Dict, Any, Tuple  # Used for type hints in function inputs and return values

import numpy as np  # Used for numerical calculations such as averages and standard deviation
import pandas as pd  # Used to load, clean, group and prepare the Excel dataset
from catboost import CatBoostRegressor  # Machine learning model used to train product value forecasting


# Columns used as input features for the machine learning model.
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


# Converts dates into the first day of their month for monthly forecasting.
def to_month_start(s: pd.Series) -> pd.Series:
    return pd.to_datetime(s, errors="coerce").dt.to_period("M").dt.to_timestamp(how="start")


# Calculates standard deviation for recent product values.
def std_last(arr: np.ndarray) -> float:
    if arr.size < 2:
        return 0.0

    return float(np.std(arr, ddof=1)) if arr.size >= 2 else 0.0


# Gets a previous product value such as 1 month, 3 months, 6 months or 12 months ago.
def lag_value(y: np.ndarray, k: int) -> float:
    if y.size == 0:
        return 0.0

    if y.size >= k:
        return float(y[-k])

    return float(y[-1])


# Builds one supervised training row using lag values and rolling statistics.
def build_row(
    y_hist: List[float],
    target_month: pd.Timestamp,
    set_name: str,
    product_name: str,
    product_category: str,
    era: str,
    set_release_date: pd.Timestamp,
) -> Dict[str, Any]:
    y = np.array(y_hist, dtype=float)

    if y.size == 0:
        return {}

    roll_3 = float(np.mean(y[-3:])) if y.size >= 3 else float(np.mean(y))
    roll_6 = float(np.mean(y[-6:])) if y.size >= 6 else float(np.mean(y))
    roll_12 = float(np.mean(y)) if y.size >= 1 else 0.0

    roll_6_std = std_last(y[-6:]) if y.size >= 2 else 0.0
    roll_12_std = std_last(y[-12:]) if y.size >= 2 else 0.0

    months_since_release = -1

    if pd.notna(set_release_date):
        rel_m = pd.to_datetime(set_release_date).to_period("M").to_timestamp(how="start")
        months_since_release = int((target_month.year - rel_m.year) * 12 + (target_month.month - rel_m.month))

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


# Loads and cleans the historical Excel dataset.
def load_excel(xlsx_path: str) -> pd.DataFrame:
    if not os.path.exists(xlsx_path):
        raise RuntimeError(f"Excel file not found: {xlsx_path}")

    df = pd.read_excel(xlsx_path, engine="openpyxl")

    required = ["Date", "Set Name", "Product Name", "Product Value"]

    for c in required:
        if c not in df.columns:
            raise RuntimeError(f"Excel is missing required column: '{c}'")

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

    df["Product Category"] = df["Product Category"].fillna("").astype(str)
    df["Era"] = df["Era"].fillna("").astype(str)

    df = df.dropna(subset=["Date", "Set Name", "Product Name", "Product Value"])
    df["month"] = to_month_start(df["Date"])

    return df


# Builds supervised training rows from the cleaned Excel data.
def build_supervised(df: pd.DataFrame) -> Tuple[pd.DataFrame, pd.Series]:
    rows = []
    targets = []

    grp_cols = ["Set Name", "Product Name", "Product Category", "Era", "Set Release Date"]

    for (set_name, product_name, product_category, era, set_release_date), g in df.groupby(grp_cols, dropna=False):
        g2 = g.groupby("month", as_index=False)["Product Value"].mean().rename(columns={"Product Value": "value"})
        g2 = g2.sort_values("month").reset_index(drop=True)

        if len(g2) < 2:
            continue

        months = g2["month"].tolist()
        values = g2["value"].astype(float).tolist()

        for i in range(1, len(months)):
            hist_vals = values[:i]
            target_val = float(values[i])
            target_month = pd.to_datetime(months[i]).to_period("M").to_timestamp(how="start")

            feat = build_row(
                y_hist=hist_vals[-12:],
                target_month=target_month,
                set_name=str(set_name),
                product_name=str(product_name),
                product_category=str(product_category),
                era=str(era),
                set_release_date=set_release_date,
            )

            if not feat:
                continue

            rows.append(feat)
            targets.append(target_val)

    if not rows:
        raise RuntimeError("No supervised rows could be built (not enough history in the spreadsheet).")

    X = pd.DataFrame(rows, columns=FEATURE_COLS)
    y = pd.Series(targets, name="y")

    return X, y


# Runs the full training process and saves model.cbm and model_meta.json.
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True)
    ap.add_argument("--out-model", default="model.cbm")
    ap.add_argument("--out-meta", default="model_meta.json")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    df = load_excel(args.xlsx)
    X, y = build_supervised(df)

    cat_cols = ["Set Name", "Product Name", "Product Category", "Era"]
    cat_idx = [X.columns.get_loc(c) for c in cat_cols]

    X = X.copy()

    for c in cat_cols:
        X[c] = X[c].fillna("").astype(str)

    model = CatBoostRegressor(
        loss_function="RMSE",
        random_seed=args.seed,
        depth=8,
        learning_rate=0.06,
        iterations=1200,
        l2_leaf_reg=6.0,
        verbose=200,
    )

    model.fit(X, y, cat_features=cat_idx)

    model.save_model(args.out_model)

    meta = {
        "feature_cols": FEATURE_COLS,
        "cat_features": cat_cols,
        "cat_feature_indices": cat_idx,
        "training_rows": int(len(X)),
    }

    with open(args.out_meta, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    print(f"Saved model -> {args.out_model}")
    print(f"Saved meta  -> {args.out_meta}")
    print(f"Rows trained: {len(X)}")


if __name__ == "__main__":
    main()