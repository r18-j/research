# Shared bar-construction parameters, used by both build_bars.R (which
# builds bars from the raw trades/bookTicker files) and
# estimation_of_market_impact.qmd (which loads the resulting bars). Keeping
# these in one place ensures the report always describes the bars that were
# actually built.

# Width of each time bar used in the "Time-Based Bars" section.
bar_interval <- "5 seconds"

# Target traded volume (in base asset units) per bin used in the
# "Volume-Based Bars" section.
volume_bin_size <- 5000

# Number of bars used in the trailing rolling window when computing the
# realised standard deviation of the pre-trade mid-price for each bar.
std_dev_window <- 120
