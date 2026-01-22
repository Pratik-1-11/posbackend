# POS Backend (Node.js + Express + PostgreSQL)

This folder contains a **separate backend service** for your POS app.

## Features

- JWT auth (access token)
- Role-based access control: `ADMIN`, `CASHIER`
- Products CRUD
- Orders create + get (transaction for order + order_items)
- PostgreSQL via `pg` (works with Supabase/Railway/Render)

## Folder structure

```
backend/
  src/
    app.js
    server.js
    config/
      env.js
      db.js
    controllers/
    services/
    routes/
    middleware/
    utils/
      db/
      jwt.js
      logger.js
      validators/
```

## Quick start (Local)

1. Install dependencies:

```bash
npm install
```

2. Create a `.env` file in `backend/` (copy from `.env.example`).

3. Create database + run migrations:

- Create a Postgres database named `pos_db` (or update `.env`).
- Run:

```bash
npm run migrate
```

4. Start the server:

```bash
npm run dev
```

Server will start on `http://localhost:5000`.

## Seed users

The migration seeds 2 users:

- Admin
  - email: `admin@pos.com`
  - password: `admin123`
- Cashier
  - email: `cashier@pos.com`
  - password: `cashier123`

## API endpoints

### Auth

- `POST /api/auth/login`
- `POST /api/auth/register` (ADMIN only)

### Users

- `GET /api/users` (ADMIN only)

### Products

- `GET /api/products` (protected)
- `GET /api/products/:id` (protected)
- `POST /api/products` (ADMIN only)
- `PUT /api/products/:id` (ADMIN only)
- `DELETE /api/products/:id` (ADMIN only)

### Orders

- `POST /api/orders` (protected)
- `GET /api/orders/:id` (protected; ADMIN can view any, CASHIER can view only their own)

## Request/Response examples

### Login

```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "admin@pos.com",
  "password": "admin123"
}
```

### Create order

```http
POST /api/orders
Authorization: Bearer <token>
Content-Type: application/json

{
  "items": [
    { "productId": 1, "quantity": 2 },
    { "productId": 2, "quantity": 1 }
  ],
  "discountAmount": 0,
  "taxAmount": 0,
  "paymentMethod": "cash"
}
```

## Deployment (Render)

### Render steps

1. Create a new **Web Service** from your GitHub repo.
2. Set **Root Directory** to `backend`.
3. Build Command:

```bash
npm install
```

4. Start Command:

```bash
npm start
```

5. Add environment variables in Render:

- `NODE_ENV=production`
- `PORT=5000` (Render provides PORT automatically; you can omit)
- `DATABASE_URL=<render postgres url>`
- `DB_SSL=true`
- `JWT_SECRET=<strong secret>`
- `JWT_EXPIRES_IN=1d`
- `CORS_ORIGIN=<your frontend url>`

### Notes

- If you use Render Postgres: copy the provided `DATABASE_URL` into the env vars.
- For Supabase: use Supabase Postgres connection string as `DATABASE_URL`.

## Status

Backend scaffolding + required APIs are implemented.
