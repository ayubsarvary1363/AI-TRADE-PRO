# RISE S TRADE recovery branch

This branch is based on the repository's main branch at commit 5568079365a9627f89d4c1d4719a206f74660a1e.

Preserved baseline capabilities include:
- 125-symbol USDT crypto watchlist.
- Binance, Kraken, and Coinbase market-data providers.
- Two-second quote refresh for the selected symbol and symbols in open positions/trade history.
- Candlestick chart with executed trade markers.
- Fast, medium-term, and long-term strategy selection.
- Timeframe selection supported by the existing provider.
- Demo account with 50 USDT starting balance and configured risk limits.
- Android foreground service foundation.

This branch also applies RISE S TRADE branding and local persistence for demo portfolio history and positions.

Important limitations that remain under development:
- Forex is not connected yet; provider setup currently reports crypto as the only supported market.
- Live orders remain disabled by the existing safety guard.
- The current background service and foreground UI create separate trading-controller instances; they need a single-engine command/state architecture before relying on background execution.
- Sub-minute custom candles and full multi-symbol signal scanning are not yet implemented.
