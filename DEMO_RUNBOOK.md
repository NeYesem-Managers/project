# NeYesem Demo

NeYesem is a demo price discovery app for comparing restaurant menu prices and flagging suspicious discounts.

This monorepo contains:

- `backend/`: Express API that normalizes scraper JSON outputs, compares prices, and exposes demo auth/profile endpoints.
- `mobile/`: Flutter demo app with login/register, deals, comparison, suspicious discounts, profile, and product analysis screens.
- `data-pipeline/`: scraper/data collection notes and an example scraper implementation.
- `database/`: database schema and helper scripts.
- `ai-service/`: AI service notes and prototype scripts.

The demo runtime does not scrape live websites. It reads previously collected real scraper outputs from:

- `backend/data/restaurants.json`
- `backend/data/getir_output/`

## Run

Backend:

```bash
cd backend
npm install
npm run dev
```

Mobile web:

```bash
cd mobile
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api
```

Android emulator:

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

## Backend Test URLs

- `http://localhost:3000/api/health`
- `http://localhost:3000/api/deals`
- `http://localhost:3000/api/suspicious-discounts`
- `http://localhost:3000/api/compare?query=tavuk`
- `http://localhost:3000/api/compare?query=pestil`
