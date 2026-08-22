# Build time- and volume-based bars from the raw Binance trades and
# bookTicker files for SOLUSD_PERP, one month at a time, so the full ~60GB
# of raw data is never loaded into memory at once.
#
# For each month this reads only the columns actually needed, aligns trades
# with the book ticker (pre_mid / post_mid), signs the trades, and builds the
# raw (unfiltered) time and volume bars, exactly as estimation_of_market_impact.qmd
# used to do for a single month. The trades and book ticker data for that
# month are then dropped and garbage-collected before moving to the next
# month.
#
# The rolling standard deviation of pre_mid_price (used later for outlier
# filtering) is computed once at the end, on the combined bars ordered by
# time, rather than per month - the bars are already a small, continuous
# time series across months, so this avoids resetting the rolling window at
# each month boundary and only loses the first std_dev_window - 1 bars of
# the whole sample instead of that many per month.
#
# Run this script with the working directory set to this project directory
# (e.g. `Rscript build_bars.R` from here, or source() it from an R session
# started in this folder), since it uses paths relative to it. Outputs are
# written to data/bars/bars_time_raw.rds and data/bars/bars_volume_raw.rds,
# which estimation_of_market_impact.qmd loads instead of the raw CSVs.

library(data.table)
library(lubridate)
library(zoo)

source("bar_params.R")

# 2024-10 is excluded: its bookTicker file is truncated (only covers
# 2024-10-01 through 2024-10-14 06:04, while the trades file for that month
# covers the full month), so trades after the 14th can't be matched to a
# pre/post mid-price and would silently drop out of the regression.
months <- sprintf("2024-%02d", 1:9)
data_dir <- "data"
out_dir <- file.path(data_dir, "bars")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

build_month_bars <- function(month) {
  message(sprintf("[%s] reading trades...", month))
  trades <- fread(
    file.path(data_dir, sprintf("SOLUSD_PERP-trades-%s.csv", month)),
    select = c("base_qty", "time", "is_buyer_maker")
  )

  message(sprintf("[%s] reading bookTicker...", month))
  bookTicker <- fread(
    file.path(data_dir, sprintf("SOLUSD_PERP-bookTicker-%s.csv", month)),
    select = c("best_bid_price", "best_ask_price", "transaction_time")
  )

  trades[, ts := as.POSIXct(time / 1000, origin = "1970-01-01", tz = "UTC")]
  bookTicker[, mid_price := (best_bid_price + best_ask_price) / 2]

  setorder(trades, time)
  setorder(bookTicker, transaction_time)
  setkey(bookTicker, transaction_time)

  message(sprintf("[%s] aligning pre/post trade mid-price...", month))
  trades[, pre_mid := bookTicker[trades, on = .(transaction_time < time), mult = "last", .(mid_price)]$mid_price]
  trades[, post_mid := bookTicker[trades, on = .(transaction_time > time), mult = "first", .(mid_price)]$mid_price]

  rm(bookTicker)
  gc()

  trades[, sign := ifelse(is_buyer_maker, -1, 1)]
  trades[, sign_base_qty := base_qty * sign]

  message(sprintf("[%s] building time bars...", month))
  bars_time <- trades[, .(
    imbalance = sum(sign_base_qty),
    base_qty = sum(base_qty),
    n_trades = .N,
    price_diff = last(post_mid) - first(pre_mid),
    pre_mid_price = first(pre_mid),
    post_mid_price = last(post_mid)
  ), by = .(bin = floor_date(ts, bar_interval))]
  bars_time[, month := month]

  message(sprintf("[%s] building volume bars...", month))
  trades[, cum_qty := cumsum(base_qty)]
  trades[, bin_id := floor(cum_qty / volume_bin_size)]

  bars_volume <- trades[, .(
    imbalance = sum(sign_base_qty),
    base_qty = sum(base_qty),
    n_trades = .N,
    price_diff = last(post_mid) - first(pre_mid),
    pre_mid_price = first(pre_mid),
    post_mid_price = last(post_mid),
    bin_time = last(ts)
  ), by = .(bin = bin_id)]
  bars_volume[, month := month]
  # bin_id restarts at 0 for every month (volume bins are sized per file, as
  # each file is processed independently), so make bin unique across the
  # combined, multi-month dataset.
  bars_volume[, bin := paste(month, bin, sep = "_")]

  rm(trades)
  gc()

  list(bars_time = bars_time, bars_volume = bars_volume)
}

bars_time_list <- vector("list", length(months))
bars_volume_list <- vector("list", length(months))

for (i in seq_along(months)) {
  month <- months[i]
  t0 <- Sys.time()
  result <- build_month_bars(month)
  bars_time_list[[i]] <- result$bars_time
  bars_volume_list[[i]] <- result$bars_volume
  message(sprintf(
    "[%s] done in %.1f min\n",
    month, as.numeric(difftime(Sys.time(), t0, units = "mins"))
  ))
}

bars_time_raw <- rbindlist(bars_time_list)
bars_volume_raw <- rbindlist(bars_volume_list)

setorder(bars_time_raw, bin)
setorder(bars_volume_raw, bin_time)

# Rolling std dev of pre_mid_price, computed once across the full, combined
# (multi-month) time series - see note at top of file.
bars_time_raw[, std_dev := rollapply(pre_mid_price, width = std_dev_window, FUN = sd, fill = NA, align = "right")]
bars_volume_raw[, std_dev := rollapply(pre_mid_price, width = std_dev_window, FUN = sd, fill = NA, align = "right")]

saveRDS(bars_time_raw, file.path(out_dir, "bars_time_raw.rds"))
saveRDS(bars_volume_raw, file.path(out_dir, "bars_volume_raw.rds"))

message(sprintf(
  "Saved %d time bars and %d volume bars to %s",
  nrow(bars_time_raw), nrow(bars_volume_raw), out_dir
))
