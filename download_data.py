import databento as db
import os

api_key = os.environ.get("DATABENTO_API_KEY")

# Initialize the historical client
client = db.Historical(api_key)

# Request continuous front-month CME Bitcoin Futures data
data = client.timeseries.get_range(
    dataset="GLBX.MDP3",
    symbols="BTC.c.0",              # Continuous lead contract
    stype_in="continuous",          # REQUIRED for continuous symbology
    schema="mbp-1",                 # Trades and Top of Book Quotes
    start="2026-08-10T00:00:00",
    end="2026-08-11T00:00:00",
)

# Replay and print the tick data
data.replay(print)

# Request static reference data / definitions
metadata = client.timeseries.get_range(
    dataset="GLBX.MDP3",
    symbols="BTC.c.0",
    stype_in="continuous",
    schema="definition",          # Changes schema from market ticks to reference metadata
    start="2026-08-10",
    end="2026-08-11",
)

# Convert to DataFrame to inspect structural columns
metadata_df = metadata.to_df()

data.to_csv(r"data/BTC_taq.csv")
metadata_df.to_csv(r"data/BTC_taq_metadata.csv")